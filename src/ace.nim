import
    os,
    strutils,
    strformat,
    parseopt,
    ace/lockfiles,
    ace/modules,
    ace/ops

when isMainModule:
    var p = initOptParser()
    var inputUrl: string
    var restoreMode = false
    var initMode = false
    var listMode = false
    var infoMode = false
    var deleteModule_name: string
    var infoModuleName: string

    for kind, key, val in p.getopt():
        if kind == cmdArgument:
            if key == "init":
                initMode = true
            elif key == "restore":
                restoreMode = true
            elif key == "list":
                listMode = true
            elif key == "info":
                infoModuleName = val
        elif kind == cmdShortOption:
            if key == "i":
                inputUrl = val
            elif key == "r":
                deleteModule_name = val
        elif kind == cmdEnd:
            break

    if initMode:
        initModuleFile()
        quit(0)

    if restoreMode:
        restoreFromLockFile()
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
        echo "ACE (v0.0.1) - Acid Code Exchange - A package manager for Acid"
        echo """

Usage: ace <options>=<params>
    
    -i=<git-repo-link>  : Install a package
    -r=<module-name>    : Remove a package

    restore             : Restore all packages from lockfile
    init                : Initialise module.acidcfg
    list                : List dependencies of current project, requires lockfile
    info <module>       : List information regarding an installed module"""

        echo "\n\e[90mNote: Installing a package that is already installed in the current acid module will update" &
             " it to the corresponding git repositories HEAD.\e[0m"
        quit(1)

    if findExe("git") == "":
        echo "Error: Git is not installed or not in PATH. Install Git."
        quit(1)

    let repoName = inputUrl.split("/")[^1].replace(".git", "")
    let cloneDir = "tmp_" & repoName

    echo "Cloning..."
    run(&"git clone --depth 1 {inputUrl} {cloneDir}")

    let moduleFile = cloneDir / "module.acidcfg"
    if not fileExists(moduleFile):
        echo "No module.acidcfg file found."
        removeDir(cloneDir)
        quit(1)

    let (moduleName, _) = parseModule(moduleFile)
    let targetDir = &"pkg/{moduleName}"
    if dirExists(targetDir):
        removeDir(targetDir)

    createDir(targetDir)
    moveDir(cloneDir, targetDir)
    echo &"Saved module to {targetDir}"
    updateLockFile(moduleName, inputUrl)
    echo "Lockfile updated."
