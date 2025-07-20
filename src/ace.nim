import
    os,
    strutils,
    strformat,
    parseopt,
    ace/lockfiles,
    ace/modules,
    ace/ops

when isMainModule:
    const version = "v0.1.1"

    var p = initOptParser()
    var inputUrl: string
    var targetVersion: string
    var restoreMode = false
    var initMode = false
    var listMode = false
    var infoMode = false
    var versionMode = false
    var upgradeMode = false
    var deleteModule_name: string
    var infoModuleName: string

    for kind, key, val in p.getopt():
        if kind == cmdArgument:
            if key == "init":
                initMode = true
            elif key == "restore":
                restoreMode = true
            elif key == "version":
                versionMode = true
            elif key == "list":
                listMode = true
            elif key == "info":
                infoMode = true
                infoModuleName = val
            elif key == "upgrade":
                upgradeMode = true
        elif kind == cmdShortOption:
            if key == "i":
                if "@" in val:
                    let parts = val.split("@", 1)
                    inputUrl = parts[0]
                    targetVersion = parts[1]
                else:
                    inputUrl = val
                    targetVersion = ""
            elif key == "r":
                deleteModule_name = val
            elif key == "v":
                targetVersion = val
        elif kind == cmdEnd:
            break

    if versionMode:
        echo version
        quit(0)

    if initMode:
        initModuleFile()
        quit(0)

    if restoreMode:
        restoreFromLockFile()
        quit(0)

    if upgradeMode:
        upgradeAllModules()
        quit(0)

    if deleteModule_name.len > 0:
        deleteModule(deleteModule_name)
        quit(0)

    if listMode:
        listModules()
        quit(0)

    if infoMode and infoModuleName.len > 0:
        showModuleInfo(infoModuleName)
        quit(0)

    if inputUrl.len == 0:
        echo &"ACE ({version}) - Acid Code Exchange - A package manager for Acid"
        echo """

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
    ace -i=https://github.com/user/repo@abc123  # Install specific commit"""
        echo "\n\e[90mNote: Installing a package that is already installed will update it to the specified version or HEAD.\e[0m"
        quit(1)

    if findExe("git") == "":
        echo "Error: Git is not installed or not in PATH. Install Git."
        quit(1)

    let repoName = inputUrl.split("/")[^1].replace(".git", "")
    let cloneDir = "tmp_" & repoName

    echo "Cloning..."

    if targetVersion.len > 0:
        runQuiet(&"git clone {inputUrl} {cloneDir}")

        let currentDir = getCurrentDir()
        setCurrentDir(cloneDir)
        let checkoutResult = execShellCmd(&"git checkout {targetVersion}")
        if checkoutResult != 0:
            echo &"Error: Could not checkout version '{targetVersion}'"
            setCurrentDir(currentDir)
            removeDir(cloneDir)
            quit(1)

        let commitHash = getGitCommitHash(".")
        setCurrentDir(currentDir)

        echo &"Checked out version {targetVersion} (commit: {commitHash[0..7]})"
    else:
        runQuiet(&"git clone --depth 1 {inputUrl} {cloneDir}")

    let moduleFile = cloneDir / "module.acidcfg"
    if not fileExists(moduleFile):
        echo "No module.acidcfg file found."
        removeDir(cloneDir)
        quit(1)

    let (moduleName, _) = parseModule(moduleFile)
    let targetDir = &"pkg/{moduleName}"

    let currentDir = getCurrentDir()
    setCurrentDir(cloneDir)
    let commitHash = getGitCommitHash(".")
    let gitTags = getGitTags(".")
    let currentBranch = getGitCurrentBranch(".")
    setCurrentDir(currentDir)

    if dirExists(targetDir):
        removeDir(targetDir)

    createDir(targetDir)
    moveDir(cloneDir, targetDir)
    echo &"Saved module to {targetDir}"
    updateLockFile(moduleName, inputUrl, commitHash, targetVersion, gitTags, currentBranch)
    echo "Lockfile updated with version information."
