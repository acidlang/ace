module apm;

import std.stdio;
import std.getopt;
import std.string;
import std.array;
import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.conv;
import std.json;
import std.datetime;
import std.typecons;
import core.stdc.stdlib;

void initModuleFile();
void restoreFromLockFile();
void upgradeAllModules();
void deleteModule(string moduleName);
void listModules();
void showModuleInfo(string moduleName);
void updateLockFile(
    string moduleName,
    string repoUrl,
    string commitHash = "",
    string requestedVersion = "",
    string[] tags = [],
    string branch = ""
);

void run(string command)
{
    auto result = executeShell(command);
    if (result.status != 0)
    {
        writefln("Command failed: %s", command);
        writefln("Error: %s", result.output);
        exit(1);
    }
}

void moveDirectory(string source, string destination)
{
    import std.algorithm : each;
    import std.range : walkLength;

    if (!exists(source))
    {
        throw new Exception("Source directory does not exist: " ~ source);
    }

    string destParent = dirName(destination);
    if (!exists(destParent))
    {
        mkdirRecurse(destParent);
    }

    try
    {
        rename(source, destination);
        return;
    }
    catch (Exception e)
    {
    }

    if (!exists(destination))
    {
        mkdirRecurse(destination);
    }

    foreach (DirEntry entry; dirEntries(source, SpanMode.breadth))
    {
        string relativePath = relativePath(entry.name, source);
        string destPath = buildPath(destination, relativePath);

        if (entry.isDir)
        {
            if (!exists(destPath))
            {
                mkdir(destPath);
            }
        }
        else
        {
            string destDir = dirName(destPath);
            if (!exists(destDir))
            {
                mkdirRecurse(destDir);
            }
            copy(entry.name, destPath);
        }
    }

    rmdirRecurse(source);
}

void runQuiet(string command)
{
    version (Windows)
    {
        command ~= " >NUL 2>&1";
    }
    else
    {
        command ~= " >/dev/null 2>&1";
    }
    auto result = executeShell(command);
    if (result.status != 0)
    {
        writefln("Command failed: %s", command.split(" >")[0]);
        exit(1);
    }
}

string getGitCommitHash(string repoPath)
{
    auto oldDir = getcwd();
    scope (exit)
        chdir(oldDir);
    chdir(repoPath);

    auto result = executeShell("git rev-parse HEAD");
    if (result.status == 0)
    {
        return result.output.strip();
    }
    return "";
}

string[] getGitTags(string repoPath)
{
    auto oldDir = getcwd();
    scope (exit)
        chdir(oldDir);
    chdir(repoPath);

    auto result = executeShell("git tag --points-at HEAD");
    if (result.status == 0 && result.output.length > 0)
    {
        return result.output.strip().split('\n').filter!(t => t.length > 0).array;
    }
    return [];
}

string getGitCurrentBranch(string repoPath)
{
    auto oldDir = getcwd();
    scope (exit)
        chdir(oldDir);
    chdir(repoPath);

    auto result = executeShell("git branch --show-current");
    if (result.status == 0)
    {
        return result.output.strip();
    }
    return "";
}

string getLatestCommitHash(string repoUrl)
{
    auto result = executeShell("git ls-remote " ~ repoUrl ~ " HEAD");
    if (result.status == 0 && result.output.length > 0)
    {
        return result.output.split('\t')[0].strip();
    }
    return "";
}

string[] getRemoteTags(string repoUrl)
{
    auto result = executeShell("git ls-remote --tags " ~ repoUrl);
    if (result.status == 0 && result.output.length > 0)
    {
        string[] tags;
        foreach (line; result.output.split('\n'))
        {
            if (line.length > 0 && !line.canFind("^{}"))
            {
                auto parts = line.split('\t');
                if (parts.length >= 2)
                {
                    string tag = parts[1].replace("refs/tags/", "");
                    tags ~= tag;
                }
            }
        }
        return tags;
    }
    return [];
}

Tuple!(string, string) parseModule(string fileName)
{
    if (!exists(fileName))
    {
        throw new Exception("Module file does not exist: " ~ fileName);
    }

    string content = readText(fileName);
    JSONValue data = parseJSON(content);

    string name = data["name"].str;
    string author = "unknown";
    if ("author" in data)
    {
        author = data["author"].str;
    }

    return tuple(name, author);
}

void initModuleFile()
{
    string cwd = baseName(getcwd());
    string projName = cwd.replace(" ", "_").toLower();

    string author = "unknown";
    version (Windows)
    {
        if (auto user = environment.get("USERNAME"))
        {
            author = user;
        }
    }
    else
    {
        if (auto user = environment.get("USER"))
        {
            author = user;
        }
    }

    JSONValue content = JSONValue([
        "name": JSONValue(projName),
        "author": JSONValue(author),
        "version": JSONValue("0.1.0")
    ]);

    string filePath = "module.acidcfg";
    if (exists(filePath))
    {
        writeln("module.acidcfg already exists. Aborting.");
        exit(1);
    }

    std.file.write(filePath, content.toPrettyString());
    writeln("Initialized module.");
}

void updateLockFile(string moduleName, string repoUrl, string commitHash = "",
    string requestedVersion = "", string[] tags = [], string branch = "")
{
    const string lockFile = "acid.lock";
    JSONValue lockData;

    if (exists(lockFile))
    {
        string content = readText(lockFile);
        lockData = parseJSON(content);
    }
    else
    {
        lockData = JSONValue((JSONValue[string]).init);
    }

    auto now = Clock.currTime();
    string timestamp = now.toISOExtString()[0 .. 19];

    JSONValue moduleEntry = JSONValue([
        "repo": JSONValue(repoUrl),
        "timestamp": JSONValue(timestamp),
        "commit_hash": JSONValue(commitHash),
        "requested_version": JSONValue(requestedVersion),
        "branch": JSONValue(branch)
    ]);

    if (tags.length > 0)
    {
        JSONValue[] tagArray;
        foreach (tag; tags)
        {
            tagArray ~= JSONValue(tag);
        }
        moduleEntry["tags"] = JSONValue(tagArray);
    }

    lockData[moduleName] = moduleEntry;
    std.file.write(lockFile, lockData.toPrettyString());
}

void removeFromLockFile(string moduleName)
{
    const string lockFile = "acid.lock";
    if (!exists(lockFile))
    {
        writeln("No " ~ lockFile ~ " found.");
        return;
    }

    string content = readText(lockFile);
    JSONValue lockData = parseJSON(content);

    if (moduleName !in lockData)
    {
        writefln("Module %s not found in lock file.", moduleName);
        return;
    }

    lockData.object.remove(moduleName);
    std.file.write(lockFile, lockData.toPrettyString());
    writefln("Removed %s from lock file.", moduleName);
}

void deleteModule(string moduleName)
{
    const string lockFile = "acid.lock";
    bool found = false;
    string targetDir = "";

    if (exists(lockFile))
    {
        string content = readText(lockFile);
        JSONValue lockData = parseJSON(content);
        if (moduleName in lockData)
        {
            found = true;
        }
    }

    string pkgDir = "pkg";
    if (exists(pkgDir) && isDir(pkgDir))
    {
        foreach (DirEntry entry; dirEntries(pkgDir, SpanMode.shallow))
        {
            if (entry.isDir)
            {
                string dirName = baseName(entry.name);
                if (dirName == moduleName)
                {
                    targetDir = entry.name;
                    found = true;
                    break;
                }
            }
        }
    }

    if (!found)
    {
        writefln("Module %s not found.", moduleName);
        exit(1);
    }

    if (targetDir != "" && exists(targetDir))
    {
        rmdirRecurse(targetDir);
        writefln("Removed module directory %s", targetDir);
    }

    removeFromLockFile(moduleName);
}

void restoreFromLockFile()
{
    const string lockFile = "acid.lock";
    if (!exists(lockFile))
    {
        writeln("No " ~ lockFile ~ " found.");
        exit(1);
    }

    string content = readText(lockFile);
    JSONValue lockData = parseJSON(content);

    foreach (string moduleName, JSONValue entry; lockData)
    {
        string repoUrl = entry["repo"].str;
        string commitHash = "";
        string requestedVersion = "";

        if ("commit_hash" in entry)
        {
            commitHash = entry["commit_hash"].str;
        }
        if ("requested_version" in entry)
        {
            requestedVersion = entry["requested_version"].str;
        }

        string repoName = baseName(repoUrl).replace(".git", "");
        string cloneDir = "tmp_" ~ repoName;

        writefln("Restoring %s from %s", moduleName, repoUrl);

        if (commitHash.length > 0)
        {
            writefln("  Target commit: %s", commitHash[0 .. min(7, $)]);
            if (requestedVersion.length > 0)
            {
                writefln("  Original version: %s", requestedVersion);
            }
        }

        run("git clone " ~ repoUrl ~ " " ~ cloneDir);

        if (commitHash.length > 0)
        {
            string currentDir = getcwd();
            chdir(cloneDir);
            auto result = executeShell("git checkout " ~ commitHash);
            chdir(currentDir);

            if (result.status != 0)
            {
                writefln("Warning: Could not checkout commit %s for %s", commitHash, moduleName);
            }
        }

        string moduleFile = buildPath(cloneDir, "module.acidcfg");
        if (!exists(moduleFile))
        {
            writefln("No module.acidcfg found for %s, skipping.", moduleName);
            rmdirRecurse(cloneDir);
            continue;
        }

        auto parsed = parseModule(moduleFile);
        string parsedName = parsed[0];
        string targetDir = buildPath("pkg", parsedName);

        if (exists(targetDir))
        {
            rmdirRecurse(targetDir);
        }

        mkdirRecurse(dirName(targetDir));
        moveDirectory(cloneDir, targetDir);
        writefln("Restored %s to %s", parsedName, targetDir);
    }
}

void upgradeAllModules()
{
    const string lockFile = "acid.lock";
    if (!exists(lockFile))
    {
        writeln("No " ~ lockFile ~ " found.");
        exit(1);
    }

    string content = readText(lockFile);
    JSONValue lockData = parseJSON(content);

    if (lockData.object.length == 0)
    {
        writeln("No modules to upgrade.");
        return;
    }

    writeln("Upgrading all modules to latest versions...");

    foreach (string moduleName, JSONValue entry; lockData)
    {
        string repoUrl = entry["repo"].str;
        string currentHash = "";
        if ("commit_hash" in entry)
        {
            currentHash = entry["commit_hash"].str;
        }

        writefln("Checking %s...", moduleName);

        string latestHash = getLatestCommitHash(repoUrl);

        if (latestHash.length > 0 && latestHash != currentHash)
        {
            writefln("  Updating from %s to %s",
                currentHash[0 .. min(7, $)], latestHash[0 .. min(7, $)]);

            string repoName = baseName(repoUrl).replace(".git", "");
            string cloneDir = "tmp_" ~ repoName;
            run("git clone --depth 1 " ~ repoUrl ~ " " ~ cloneDir);

            string moduleFile = buildPath(cloneDir, "module.acidcfg");
            if (!exists(moduleFile))
            {
                writefln("  Warning: No module.acidcfg found, skipping %s", moduleName);
                rmdirRecurse(cloneDir);
                continue;
            }

            string targetDir = buildPath("pkg", moduleName);
            if (exists(targetDir))
            {
                rmdirRecurse(targetDir);
            }

            mkdirRecurse(dirName(targetDir));
            moveDirectory(cloneDir, targetDir);

            string newCommitHash = getGitCommitHash(targetDir);
            string[] newTags = getGitTags(targetDir);
            string newBranch = getGitCurrentBranch(targetDir);

            updateLockFile(moduleName, repoUrl, newCommitHash, "", newTags, newBranch);
            writefln("  Updated %s", moduleName);
        }
        else
        {
            writefln("  %s is already up to date", moduleName);
        }
    }
}

void listModules()
{
    const string lockFile = "acid.lock";
    if (!exists(lockFile))
    {
        writeln("No acid.lock file found.");
        exit(1);
    }

    string content = readText(lockFile);
    JSONValue lockData = parseJSON(content);

    if (lockData.object.length == 0)
    {
        writeln("No modules installed.");
        return;
    }

    foreach (string key, JSONValue entry; lockData)
    {
        string repo = entry["repo"].str;
        string timestamp = entry["timestamp"].str;
        string commitHash = "";
        string requestedVersion = "";

        if ("commit_hash" in entry)
        {
            commitHash = entry["commit_hash"].str;
        }
        if ("requested_version" in entry)
        {
            requestedVersion = entry["requested_version"].str;
        }

        string versionInfo = "";
        if (requestedVersion.length > 0)
        {
            versionInfo = " (v" ~ requestedVersion ~ ")";
        }
        else if (commitHash.length > 0)
        {
            versionInfo = " (" ~ commitHash[0 .. min(7, $)] ~ ")";
        }

        writefln("- %s%s @ %s (installed %s)", key, versionInfo, repo, timestamp);
    }
}

void showModuleInfo(string moduleName)
{
    const string lockFile = "acid.lock";
    if (!exists(lockFile))
    {
        writeln("No acid.lock file found.");
        exit(1);
    }

    string content = readText(lockFile);
    JSONValue lockData = parseJSON(content);

    if (moduleName !in lockData)
    {
        writefln("Module '%s' not found in lock file.", moduleName);
        exit(1);
    }

    JSONValue entry = lockData[moduleName];
    string repo = entry["repo"].str;
    string tstamp = entry["timestamp"].str;
    string commitHash = "";
    string requestedVersion = "";
    string branch = "";

    if ("commit_hash" in entry)
    {
        commitHash = entry["commit_hash"].str;
    }
    if ("requested_version" in entry)
    {
        requestedVersion = entry["requested_version"].str;
    }
    if ("branch" in entry)
    {
        branch = entry["branch"].str;
    }

    writefln("Module: %s", moduleName);
    writefln("Repository: %s", repo);
    writefln("Installed At: %s", tstamp);

    if (requestedVersion.length > 0)
    {
        writefln("Requested Version: %s", requestedVersion);
    }

    if (commitHash.length > 0)
    {
        writefln("Commit Hash: %s", commitHash);
    }

    if (branch.length > 0)
    {
        writefln("Branch: %s", branch);
    }

    if ("tags" in entry)
    {
        JSONValue[] tags = entry["tags"].array;
        if (tags.length > 0)
        {
            string[] tagStrs;
            foreach (tag; tags)
            {
                tagStrs ~= tag.str;
            }
            writefln("Tags: %s", tagStrs.join(", "));
        }
    }

    string moduleCfg = buildPath("pkg", moduleName, "module.acidcfg");
    if (exists(moduleCfg))
    {
        string cfgContent = readText(moduleCfg);
        JSONValue cfgData = parseJSON(cfgContent);

        if ("author" in cfgData)
        {
            writefln("Author: %s", cfgData["author"].str);
        }
        if ("version" in cfgData)
        {
            writefln("Module Version: %s", cfgData["version"].str);
        }
    }
    else
    {
        writeln("Warning: module.acidcfg not found in pkg/ directory");
    }
}

int main(string[] args)
{
    const string ver = "v0.1.1";

    string inputUrl;
    string targetVersion;
    bool restoreMode = false;
    bool initMode = false;
    bool listMode = false;
    bool infoMode = false;
    bool versionMode = false;
    bool upgradeMode = false;
    string deleteModule_name;
    string infoModuleName;

    try
    {
        auto helpInformation = getopt(args,
            "i", "Install a package (optionally at specific version)", &inputUrl,
            "r", "Remove a package", &deleteModule_name,
            "v", "Specify version (tag, branch, or commit hash)", &targetVersion);

        if (helpInformation.helpWanted)
        {
            defaultGetoptPrinter("ACE Package Manager", helpInformation.options);
            return 0;
        }

        foreach (arg; args[1 .. $])
        {
            switch (arg)
            {
            case "init":
                initMode = true;
                break;
            case "restore":
                restoreMode = true;
                break;
            case "version":
                versionMode = true;
                break;
            case "list":
                listMode = true;
                break;
            case "upgrade":
                upgradeMode = true;
                break;
            default:
                if (arg.startsWith("info"))
                {
                    infoMode = true;
                    auto parts = arg.split(" ");
                    if (parts.length > 1)
                    {
                        infoModuleName = parts[1];
                    }
                }
                break;
            }
        }

        if (inputUrl.canFind("@"))
        {
            auto parts = inputUrl.split("@");
            if (parts.length == 2)
            {
                inputUrl = parts[0];
                targetVersion = parts[1];
            }
        }
    }
    catch (Exception e)
    {
        writeln("Error parsing arguments: ", e.msg);
        return 1;
    }

    if (versionMode)
    {
        writeln(ver);
        return 0;
    }

    if (initMode)
    {
        initModuleFile();
        return 0;
    }

    if (restoreMode)
    {
        restoreFromLockFile();
        return 0;
    }

    if (upgradeMode)
    {
        upgradeAllModules();
        return 0;
    }

    if (deleteModule_name.length > 0)
    {
        deleteModule(deleteModule_name);
        return 0;
    }

    if (listMode)
    {
        listModules();
        return 0;
    }

    if (infoMode && infoModuleName.length > 0)
    {
        showModuleInfo(infoModuleName);
        return 0;
    }

    if (inputUrl.length == 0)
    {
        writefln("ACE (%s) - Acid Code Exchange - A package manager for Acid", ver);
        writeln(`
Usage: ace <options>=<params>

    -i=<git-repo-link>[@version] : Install a package (optionally at specific version)
    -r=<module-name>             : Remove a package
    -v=<version>                 : Specify version (tag, branch, or commit hash)
    restore                      : Restore all packages from lockfile
    upgrade                      : Upgrade all packages to latest versions
    version                      : Show installed version of ace
    init                         : Initialise module.acidcfg
    list                         : List dependencies of current project, requires lockfile
    info <module>                : List information regarding an installed module

Version Examples:
    ace -i=https://github.com/user/repo@v1.2.3  # Install specific tag
    ace -i=https://github.com/user/repo@main    # Install specific branch
    ace -i=https://github.com/user/repo@abc123  # Install specific commit`);
        writeln("\n\033[90mNote: Installing a package that is" ~
                " already installed will update it to the specified version or HEAD.\033[0m");
        return 1;
    }

    auto gitCheck = executeShell("git --version");
    if (gitCheck.status != 0)
    {
        writeln("Error: Git is not installed or not in PATH. Install Git.");
        return 1;
    }

    string repoName = baseName(inputUrl).replace(".git", "");
    string cloneDir = "tmp_" ~ repoName;

    writeln("Cloning...");

    if (targetVersion.length > 0)
    {
        run("git clone " ~ inputUrl ~ " " ~ cloneDir);

        string currentDir = getcwd();
        chdir(cloneDir);
        auto checkoutResult = executeShell("git checkout " ~ targetVersion);
        if (checkoutResult.status != 0)
        {
            writefln("Error: Could not checkout version '%s'", targetVersion);
            chdir(currentDir);
            rmdirRecurse(cloneDir);
            return 1;
        }

        string commitHash = getGitCommitHash(".");
        chdir(currentDir);

        writefln("Checked out version %s (commit: %s)", targetVersion, commitHash[0 .. min(7, $)]);
    }
    else
    {
        run("git clone --depth 1 " ~ inputUrl ~ " " ~ cloneDir);
    }

    string moduleFile = buildPath(cloneDir, "module.acidcfg");
    if (!exists(moduleFile))
    {
        writeln("No module.acidcfg file found.");
        rmdirRecurse(cloneDir);
        return 1;
    }

    auto parsed = parseModule(moduleFile);
    string moduleName = parsed[0];
    string targetDir = buildPath("pkg", moduleName);

    string currentDir = getcwd();
    chdir(cloneDir);
    string commitHash = getGitCommitHash(".");
    string[] gitTags = getGitTags(".");
    string currentBranch = getGitCurrentBranch(".");
    chdir(currentDir);

    if (exists(targetDir))
    {
        rmdirRecurse(targetDir);
    }

    mkdirRecurse(dirName(targetDir));
    moveDirectory(cloneDir, targetDir);
    writefln("Saved module to %s", targetDir);

    updateLockFile(moduleName, inputUrl, commitHash, targetVersion, gitTags, currentBranch);
    writeln("Lockfile updated with version information.");

    return 0;
}
