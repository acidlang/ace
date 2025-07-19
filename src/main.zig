const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const json = std.json;
const fs = std.fs;
const process = std.process;

const AceError = error{
    InvalidArguments,
    GitNotFound,
    ModuleNotFound,
    LockFileNotFound,
    InvalidModuleConfig,
    DirectoryNotFound,
    FileOperationFailed,
};

const Module = struct {
    name: []const u8,
    author: []const u8,

    fn deinit(self: *Module, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.author);
    }
};

const LockEntry = struct {
    repo: []const u8,
    timestamp: []const u8,

    fn deinit(self: *LockEntry, allocator: Allocator) void {
        allocator.free(self.repo);
        allocator.free(self.timestamp);
    }
};

const Options = struct {
    install_url: ?[]const u8 = null,
    remove_module: ?[]const u8 = null,
    info_module: ?[]const u8 = null,
    init_mode: bool = false,
    restore_mode: bool = false,
    list_mode: bool = false,
    info_mode: bool = false,
};

fn runCommand(allocator: Allocator, cmd: []const u8) !void {
    var argv = ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    var it = std.mem.splitSequence(u8, cmd, " ");
    while (it.next()) |part| {
        try argv.append(part);
    }

    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    const result = try child.spawnAndWait();
    if (result != .Exited or result.Exited != 0) {
        return AceError.FileOperationFailed;
    }
}

fn fileExists(path: []const u8) bool {
    fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn dirExists(path: []const u8) bool {
    var dir = fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

fn createDir(path: []const u8) !void {
    fs.cwd().makeDir(path) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
}

fn removeDir(path: []const u8) !void {
    try fs.cwd().deleteTree(path);
}

fn moveDir(allocator: Allocator, src: []const u8, dst: []const u8) !void {
    const cmd = try std.fmt.allocPrint(allocator, "mv {s} {s}", .{ src, dst });
    defer allocator.free(cmd);
    try runCommand(allocator, cmd);
}

fn readFile(allocator: Allocator, path: []const u8) ![]u8 {
    const file = fs.cwd().openFile(path, .{}) catch return AceError.FileOperationFailed;
    defer file.close();

    const file_size = try file.getEndPos();
    const contents = try allocator.alloc(u8, file_size);
    _ = try file.readAll(contents);
    return contents;
}

fn writeFile(path: []const u8, content: []const u8) !void {
    const file = fs.cwd().createFile(path, .{}) catch return AceError.FileOperationFailed;
    defer file.close();
    try file.writeAll(content);
}

fn getCurrentTimestamp(allocator: Allocator) ![]u8 {
    const timestamp = std.time.timestamp();
    const epoch_seconds = @as(u64, @intCast(timestamp));
    const seconds_per_day = 24 * 60 * 60;
    const seconds_per_hour = 60 * 60;
    const seconds_per_minute = 60;

    const days_since_epoch = epoch_seconds / seconds_per_day;
    const remaining_seconds = epoch_seconds % seconds_per_day;

    const hours = remaining_seconds / seconds_per_hour;
    const minutes = (remaining_seconds % seconds_per_hour) / seconds_per_minute;
    const seconds = remaining_seconds % seconds_per_minute;
    const year = 1970 + days_since_epoch / 365;
    const month = ((days_since_epoch % 365) / 30) + 1;
    const day = ((days_since_epoch % 365) % 30) + 1;

    return try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{ year, month, day, hours, minutes, seconds });
}

fn parseModule(allocator: Allocator, file_path: []const u8) !Module {
    const content = try readFile(allocator, file_path);
    defer allocator.free(content);

    var parsed = json.parseFromSlice(json.Value, allocator, content, .{}) catch return AceError.InvalidModuleConfig;
    defer parsed.deinit();

    const name = parsed.value.object.get("name") orelse return AceError.InvalidModuleConfig;
    const author = parsed.value.object.get("author") orelse return AceError.InvalidModuleConfig;

    return Module{
        .name = try allocator.dupe(u8, name.string),
        .author = try allocator.dupe(u8, author.string),
    };
}

fn initModuleFile(allocator: Allocator) !void {
    if (fileExists("module.acidcfg")) {
        print("module.acidcfg already exists. Aborting.\n");
        std.process.exit(1);
    }

    const cwd = fs.cwd().realpathAlloc(allocator, ".") catch return AceError.FileOperationFailed;
    defer allocator.free(cwd);

    const basename = fs.path.basename(cwd);
    var proj_name = ArrayList(u8).init(allocator);
    defer proj_name.deinit();

    for (basename) |c| {
        if (c == ' ') {
            try proj_name.append('_');
        } else {
            try proj_name.append(std.ascii.toLower(c));
        }
    }

    const author = std.process.getEnvVarOwned(allocator, "USER") catch
        std.process.getEnvVarOwned(allocator, "USERNAME") catch
        try allocator.dupe(u8, "unknown");
    defer allocator.free(author);

    const content = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "name": "{s}",
        \\  "author": "{s}"
        \\}}
    , .{ proj_name.items, author });
    defer allocator.free(content);

    try writeFile("module.acidcfg", content);
    print("Initialized module.\n");
}

fn updateLockFile(allocator: Allocator, module_name: []const u8, repo_url: []const u8) !void {
    const lock_file = "acid.lock";
    var lock_data: json.Value = undefined;
    var parsed: ?json.Parsed(json.Value) = null;

    if (fileExists(lock_file)) {
        const content = try readFile(allocator, lock_file);
        defer allocator.free(content);
        parsed = json.parseFromSlice(json.Value, allocator, content, .{}) catch null;
        if (parsed) |p| {
            lock_data = p.value;
        } else {
            lock_data = json.Value{ .object = json.ObjectMap.init(allocator) };
        }
    } else {
        lock_data = json.Value{ .object = json.ObjectMap.init(allocator) };
    }

    const timestamp = try getCurrentTimestamp(allocator);
    defer allocator.free(timestamp);

    var entry_map = json.ObjectMap.init(allocator);
    try entry_map.put("repo", json.Value{ .string = try allocator.dupe(u8, repo_url) });
    try entry_map.put("timestamp", json.Value{ .string = try allocator.dupe(u8, timestamp) });

    try lock_data.object.put(try allocator.dupe(u8, module_name), json.Value{ .object = entry_map });

    var string = ArrayList(u8).init(allocator);
    defer string.deinit();
    try json.stringify(lock_data, .{}, string.writer());

    try writeFile(lock_file, string.items);

    if (parsed) |p| p.deinit();
}

fn removeFromLockFile(allocator: Allocator, module_name: []const u8) !void {
    const lock_file = "acid.lock";
    if (!fileExists(lock_file)) {
        std.debug.print("No {s} found.\n", .{lock_file});
        return;
    }

    const content = try readFile(allocator, lock_file);
    defer allocator.free(content);

    var parsed = json.parseFromSlice(json.Value, allocator, content, .{}) catch return AceError.InvalidModuleConfig;
    defer parsed.deinit();

    if (!parsed.value.object.contains(module_name)) {
        std.debug.print("Module {s} not found in lock file.\n", .{module_name});
        return;
    }

    _ = parsed.value.object.swapRemove(module_name);

    var string = ArrayList(u8).init(allocator);
    defer string.deinit();
    try json.stringify(parsed.value, .{}, string.writer());

    try writeFile(lock_file, string.items);
    std.debug.print("Removed {s} from lock file.\n", .{module_name});
}

fn deleteModule(allocator: Allocator, module_name: []const u8) !void {
    const lock_file = "acid.lock";
    var found = false;
    var target_dir: ?[]u8 = null;

    if (fileExists(lock_file)) {
        const content = try readFile(allocator, lock_file);
        defer allocator.free(content);

        var parsed = json.parseFromSlice(json.Value, allocator, content, .{}) catch return AceError.InvalidModuleConfig;
        defer parsed.deinit();

        if (parsed.value.object.contains(module_name)) {
            found = true;
            if (dirExists("pkg")) {
                var pkg_dir = fs.cwd().openDir("pkg", .{}) catch return AceError.DirectoryNotFound;
                defer pkg_dir.close();

                var iterator = pkg_dir.iterate();
                while (try iterator.next()) |entry| {
                    if (entry.kind == .directory) {
                        if (std.mem.startsWith(u8, entry.name, module_name)) {
                            target_dir = try std.fmt.allocPrint(allocator, "pkg/{s}", .{entry.name});
                            break;
                        }
                    }
                }
            }
        }
    }

    if (!found) {
        if (dirExists("pkg")) {
            var pkg_dir = fs.cwd().openDir("pkg", .{}) catch return AceError.DirectoryNotFound;
            defer pkg_dir.close();

            var iterator = pkg_dir.iterate();
            while (try iterator.next()) |entry| {
                if (entry.kind == .directory) {
                    if (std.mem.startsWith(u8, entry.name, module_name)) {
                        target_dir = try std.fmt.allocPrint(allocator, "pkg/{s}", .{entry.name});
                        found = true;
                        break;
                    }
                }
            }
        }
    }

    if (!found) {
        std.debug.print("Module {s} not found.\n", .{module_name});
        std.process.exit(1);
    }

    if (target_dir) |dir| {
        defer allocator.free(dir);
        if (dirExists(dir)) {
            try removeDir(dir);
            std.debug.print("Removed module directory {s}\n", .{dir});
        }
    }

    try removeFromLockFile(allocator, module_name);
}

fn restoreFromLockFile(allocator: Allocator) !void {
    const lock_file = "acid.lock";
    if (!fileExists(lock_file)) {
        std.debug.print("No {s} found.\n", .{lock_file});
        std.process.exit(1);
    }

    const content = try readFile(allocator, lock_file);
    defer allocator.free(content);

    var parsed = json.parseFromSlice(json.Value, allocator, content, .{}) catch return AceError.InvalidModuleConfig;
    defer parsed.deinit();

    var iterator = parsed.value.object.iterator();
    while (iterator.next()) |entry| {
        const module_name = entry.key_ptr.*;
        const module_data = entry.value_ptr.*;

        const repo_url = module_data.object.get("repo").?.string;

        var repo_name: []const u8 = undefined;
        if (std.mem.lastIndexOf(u8, repo_url, "/")) |last_slash| {
            repo_name = repo_url[last_slash + 1 ..];
            if (std.mem.endsWith(u8, repo_name, ".git")) {
                repo_name = repo_name[0 .. repo_name.len - 4];
            }
        } else {
            repo_name = repo_url;
        }

        const clone_dir = try std.fmt.allocPrint(allocator, "tmp_{s}", .{repo_name});
        defer allocator.free(clone_dir);

        std.debug.print("Restoring {s} from {s}\n", .{ module_name, repo_url });

        const git_cmd = try std.fmt.allocPrint(allocator, "git clone --depth 1 {s} {s}", .{ repo_url, clone_dir });
        defer allocator.free(git_cmd);
        try runCommand(allocator, git_cmd);

        const module_file = try std.fmt.allocPrint(allocator, "{s}/module.acidcfg", .{clone_dir});
        defer allocator.free(module_file);

        if (!fileExists(module_file)) {
            std.debug.print("No module.acidcfg found for {s}, skipping.\n", .{module_name});
            try removeDir(clone_dir);
            continue;
        }

        var module_info = parseModule(allocator, module_file) catch {
            try removeDir(clone_dir);
            continue;
        };
        defer module_info.deinit(allocator);

        const target_dir = try std.fmt.allocPrint(allocator, "pkg/{s}", .{module_info.name});
        defer allocator.free(target_dir);

        if (dirExists(target_dir)) {
            try removeDir(target_dir);
        }
        try createDir("pkg");
        try moveDir(allocator, clone_dir, target_dir);
        std.debug.print("Restored {s} to {s}\n", .{ module_info.name, target_dir });
    }
}

fn listModules(allocator: Allocator) !void {
    const lock_file = "acid.lock";
    if (!fileExists(lock_file)) {
        print("No acid.lock file found.\n");
        std.process.exit(1);
    }

    const content = try readFile(allocator, lock_file);
    defer allocator.free(content);

    var parsed = json.parseFromSlice(json.Value, allocator, content, .{}) catch return AceError.InvalidModuleConfig;
    defer parsed.deinit();

    if (parsed.value.object.count() == 0) {
        print("No modules installed.\n");
        return;
    }

    print("Installed Modules:\n");
    var iterator = parsed.value.object.iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        const repo = value.object.get("repo").?.string;
        const timestamp = value.object.get("timestamp").?.string;
        std.debug.print("- {s} @ {s} (installed {s})\n", .{ key, repo, timestamp });
    }
}

fn showModuleInfo(allocator: Allocator, module_name: []const u8) !void {
    const lock_file = "acid.lock";
    if (!fileExists(lock_file)) {
        print("No acid.lock file found.\n");
        std.process.exit(1);
    }

    const content = try readFile(allocator, lock_file);
    defer allocator.free(content);

    var parsed = json.parseFromSlice(json.Value, allocator, content, .{}) catch return AceError.InvalidModuleConfig;
    defer parsed.deinit();

    if (!parsed.value.object.contains(module_name)) {
        std.debug.print("Module '{s}' not found in lock file.\n", .{module_name});
        std.process.exit(1);
    }

    const entry = parsed.value.object.get(module_name).?;
    const repo = entry.object.get("repo").?.string;
    const timestamp = entry.object.get("timestamp").?.string;

    std.debug.print("Module: {s}\n", .{module_name});
    std.debug.print("Repository: {s}\n", .{repo});
    std.debug.print("Installed At: {s}\n", .{timestamp});

    const module_cfg = try std.fmt.allocPrint(allocator, "pkg/{s}/module.acidcfg", .{module_name});
    defer allocator.free(module_cfg);

    if (fileExists(module_cfg)) {
        const cfg_content = try readFile(allocator, module_cfg);
        defer allocator.free(cfg_content);

        var cfg_parsed = json.parseFromSlice(json.Value, allocator, cfg_content, .{}) catch return;
        defer cfg_parsed.deinit();

        if (cfg_parsed.value.object.get("author")) |author| {
            std.debug.print("Author: {s}\n", .{author.string});
        }
        if (cfg_parsed.value.object.get("version")) |version| {
            std.debug.print("Version: {s}\n", .{version.string});
        }
    } else {
        print("Warning: module.acidcfg not found in pkg/\n");
    }
}

fn checkGitInstalled(allocator: Allocator) !void {
    runCommand(allocator, "git --version") catch {
        print("Error: Git is not installed or not in PATH. Install Git.\n");
        std.process.exit(1);
    };
}

fn parseArgs(allocator: Allocator) !Options {
    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    var options = Options{};
    var i: usize = 1;

    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "init")) {
            options.init_mode = true;
        } else if (std.mem.eql(u8, arg, "restore")) {
            options.restore_mode = true;
        } else if (std.mem.eql(u8, arg, "list")) {
            options.list_mode = true;
        } else if (std.mem.eql(u8, arg, "info") and i + 1 < args.len) {
            options.info_mode = true;
            i += 1;
            options.info_module = args[i];
        } else if (std.mem.startsWith(u8, arg, "-i=")) {
            options.install_url = arg[3..];
        } else if (std.mem.startsWith(u8, arg, "-r=")) {
            options.remove_module = arg[3..];
        }

        i += 1;
    }

    return options;
}

fn print(thing: []const u8) void {
    std.debug.print("{s}", .{thing});
}

fn printUsage() void {
    print("ACE (v0.0.1) - Acid Code Exchange - A package manager for Acid\n");
    print("\nUsage: ace <options>=<params>\n");
    print("   \n");
    print("    -i=<git-repo-link>  : Install a package\n");
    print("    -r=<module-name>    : Remove a package\n");
    print("    restore             : Restore all packages from lockfile\n");
    print("    init                : Initialise module.acidcfg\n");
    print("    list                : List dependencies of current project, requires lockfile\n");
    print("    info <module>       : List information regarding an installed module\n");
    print("\n\x1b[90mNote: Installing a package that is already installed in the current acid module will update it to the corresponding git repositories HEAD.\x1b[0m\n");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options = parseArgs(allocator) catch {
        printUsage();
        std.process.exit(1);
        return;
    };

    if (options.init_mode) {
        try initModuleFile(allocator);
        return;
    }

    if (options.restore_mode) {
        try restoreFromLockFile(allocator);
        return;
    }

    if (options.remove_module) |module_name| {
        try deleteModule(allocator, module_name);
        return;
    }

    if (options.list_mode) {
        try listModules(allocator);
        return;
    }

    if (options.info_mode) {
        if (options.info_module) |module_name| {
            try showModuleInfo(allocator, module_name);
            return;
        }
    }

    if (options.install_url) |url| {
        try checkGitInstalled(allocator);
        var repo_name: []const u8 = undefined;
        if (std.mem.lastIndexOf(u8, url, "/")) |last_slash| {
            repo_name = url[last_slash + 1 ..];
            if (std.mem.endsWith(u8, repo_name, ".git")) {
                repo_name = repo_name[0 .. repo_name.len - 4];
            }
        } else {
            repo_name = url;
        }

        const clone_dir = try std.fmt.allocPrint(allocator, "tmp_{s}", .{repo_name});
        defer allocator.free(clone_dir);

        print("Cloning...\n");
        const git_cmd = try std.fmt.allocPrint(allocator, "git clone --depth 1 {s} {s}", .{ url, clone_dir });
        defer allocator.free(git_cmd);
        try runCommand(allocator, git_cmd);

        const module_file = try std.fmt.allocPrint(allocator, "{s}/module.acidcfg", .{clone_dir});
        defer allocator.free(module_file);

        if (!fileExists(module_file)) {
            print("No module.acidcfg file found.\n");
            try removeDir(clone_dir);
            std.process.exit(1);
        }

        var module_info = parseModule(allocator, module_file) catch {
            print("Invalid module.acidcfg file.\n");
            try removeDir(clone_dir);
            std.process.exit(1);
        };
        defer module_info.deinit(allocator);

        const target_dir = try std.fmt.allocPrint(allocator, "pkg/{s}", .{module_info.name});
        defer allocator.free(target_dir);

        if (dirExists(target_dir)) {
            try removeDir(target_dir);
        }
        try createDir("pkg");
        try moveDir(allocator, clone_dir, target_dir);
        std.debug.print("Saved module to {s}\n", .{target_dir});

        try updateLockFile(allocator, module_info.name, url);
        print("Lockfile updated.\n");
        return;
    }

    printUsage();
    std.process.exit(1);
}
