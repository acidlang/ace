module apm;

import std.stdio;
import std.process;
import std.file;
import std.path;
import std.string;
import std.format;
import std.getopt;
import std.datetime;
import std.json;
import std.algorithm;
import std.array;
import core.stdc.stdlib;

struct ModuleInfo
{
    string name;
    string author;
}

ModuleInfo parseModule(string file)
{
    string content = readText(file);
    JSONValue data = parseJSON(content);
    return ModuleInfo(data["name"].str, data["author"].str);
}

void run(string cmd)
{
    executeShell(cmd);
}

void updateLockFile(string moduleName, string repoUrl)
{
    enum lockFile = "acid.lock";
    JSONValue lockData;

    if (exists(lockFile))
        lockData = parseJSON(readText(lockFile));
    else
        lockData = JSONValue.emptyObject;

    auto timestamp = Clock.currTime().toISOExtString();
    lockData[moduleName] = JSONValue([
        "repo": JSONValue(repoUrl),
        "timestamp": JSONValue(timestamp)
    ]);

    std.file.write(lockFile, lockData.toPrettyString());
}

void removeFromLockFile(string moduleName)
{
    enum lockFile = "acid.lock";
    if (!exists(lockFile))
    {
        writeln("No " ~ lockFile ~ " found.");
        return;
    }

    JSONValue lockData = parseJSON(readText(lockFile));
    if (moduleName !in lockData.object)
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
    enum lockFile = "acid.lock";
    bool found = false;
    string targetDir = "";

    if (exists(lockFile))
    {
        JSONValue lockData = parseJSON(readText(lockFile));
        if (moduleName in lockData.object)
        {
            found = true;
            enum pkgDir = "pkg";
            if (exists(pkgDir) && isDir(pkgDir))
            {
                foreach (DirEntry entry; dirEntries(pkgDir, SpanMode.shallow))
                {
                    if (entry.isDir)
                    {
                        string dirName = baseName(entry.name);
                        if (dirName.startsWith(moduleName ~ "_"))
                        {
                            targetDir = entry.name;
                            break;
                        }
                    }
                }
            }
        }
    }

    if (!found)
    {
        enum pkgDir = "pkg";
        if (exists(pkgDir) && isDir(pkgDir))
        {
            foreach (DirEntry entry; dirEntries(pkgDir, SpanMode.shallow))
            {
                if (entry.isDir)
                {
                    string dirName = baseName(entry.name);
                    if (dirName.startsWith(moduleName ~ "_"))
                    {
                        targetDir = entry.name;
                        found = true;
                        break;
                    }
                }
            }
        }
    }

    if (!found)
    {
        writefln("Module %s not found.", moduleName);
        exit(1);
    }

    if (targetDir != "" && exists(targetDir) && isDir(targetDir))
    {
        rmdirRecurse(targetDir);
        writefln("Removed module directory %s", targetDir);
    }

    removeFromLockFile(moduleName);
}

void restoreFromLockFile()
{
    enum lockFile = "acid.lock";
    if (!exists(lockFile))
    {
        writeln("No " ~ lockFile ~ " found.");
        exit(1);
    }

    JSONValue lockData = parseJSON(readText(lockFile));
    foreach (string moduleName, JSONValue moduleData; lockData.object)
    {
        string repoUrl = moduleData["repo"].str;
        string repoName = repoUrl.split("/")[$ - 1].replace(".git", "");
        string cloneDir = "tmp_" ~ repoName;

        writefln("Restoring %s from %s", moduleName, repoUrl);
        run(format("git clone --depth 1 %s %s", repoUrl, cloneDir));

        string moduleFile = buildPath(cloneDir, "module.acidcfg");
        if (!exists(moduleFile))
        {
            writefln("No module.acidcfg found for %s, skipping.", moduleName);
            rmdirRecurse(cloneDir);
            continue;
        }

        ModuleInfo info = parseModule(moduleFile);
        string targetDir = format("pkg/%s", info.name);

        if (exists(targetDir) && isDir(targetDir))
        {
            rmdirRecurse(targetDir);
        }
        mkdirRecurse(targetDir);
        rename(cloneDir, targetDir);

        writefln("Restored %s to %s", info.name, targetDir);
    }
}

void initModuleFile()
{
    string cwd = baseName(getcwd());
    string projName = cwd.replace(" ", "_").toLower();

    import std.process : environment;

    string author = environment.get("USER", environment.get("USERNAME", "unknown"));

    JSONValue content = JSONValue([
        "name": JSONValue(projName),
        "author": JSONValue(author)
    ]);

    enum filePath = "module.acidcfg";

    if (exists(filePath))
    {
        writeln("module.acidcfg already exists. Aborting.");
        exit(1);
    }

    std.file.write(filePath, content.toPrettyString());
    writeln("Initialized module.");
}

void main(string[] args)
{
    string inputUrl;
    bool restoreMode = false;
    bool initMode = false;
    string deleteModuleName;

    try
    {
        auto helpInformation = getopt(
            args,
            "i|install", "Install a package from git repository", &inputUrl,
            "r|remove", "Remove a package", &deleteModuleName
        );

        if (helpInformation.helpWanted)
        {
            defaultGetoptPrinter("ACE (v0.0.1) - Acid Code Exchange - A package manager for Acid",
                helpInformation.options);
            return;
        }

        if (args.length > 1)
        {
            if (args[1] == "init")
            {
                initMode = true;
            }
            else if (args[1] == "restore")
            {
                restoreMode = true;
            }
        }

        if (initMode)
        {
            initModuleFile();
            return;
        }

        if (restoreMode)
        {
            restoreFromLockFile();
            return;
        }

        if (deleteModuleName.length > 0)
        {
            deleteModule(deleteModuleName);
            return;
        }

        if (inputUrl.length == 0)
        {
            writeln(`
ACE (v0.0.1) - Acid Code Exchange - A package manager for Acid

Usage: ace <options>=<params>
    
    -i, --install=<git-repo-link>  : Install a package
    -r, --remove=<module-name>     : Remove a package

    restore                        : Restore all packages from lockfile
    init                           : Initialise module.acidcfg
    
Note: Installing a package that is already installed in the current acid module will update it to the
corresponding git repositories HEAD.`);
            exit(1);
        }

        auto gitResult = executeShell("git --version");
        if (gitResult.status != 0)
        {
            writeln("Error: Git is not installed or not in PATH. Install Git.");
            exit(1);
        }

        string repoName = inputUrl.split("/")[$ - 1].replace(".git", "");
        string cloneDir = "tmp_" ~ repoName;

        writeln("Cloning...");
        run(format("git clone --depth 1 %s %s", inputUrl, cloneDir));

        string moduleFile = buildPath(cloneDir, "module.acidcfg");
        if (!exists(moduleFile))
        {
            writeln("No module.acidcfg file found.");
            rmdirRecurse(cloneDir);
            exit(1);
        }

        ModuleInfo info = parseModule(moduleFile);
        string targetDir = format("pkg/%s", info.name);

        if (exists(targetDir) && isDir(targetDir))
        {
            rmdirRecurse(targetDir);
        }

        mkdirRecurse(targetDir);
        rename(cloneDir, targetDir);
        writefln("Saved module to %s", targetDir);
        updateLockFile(info.name, inputUrl);
        writeln("Lockfile updated.");

    }
    catch (Exception e)
    {
        writefln("Error: %s", e.msg);
        exit(1);
    }
}
