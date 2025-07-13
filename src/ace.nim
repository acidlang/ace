import
    os,
    osproc,
    strutils,
    strformat,
    parseopt,
    times,
    json,
    checksums/sha1

proc runShell(cmd: string): string =
    result = execProcess(cmd)

proc sha1Hash(s: string): string =
    return $sha1.secureHash(s)

proc parseModule(file: string): (string, string) =
    ## Extract module name and author from module.acidcfg
    ## (format: JSON with name and author fields)
    let content = readFile(file)
    let data = parseJson(content)
    result = (data["name"].getStr(), data["author"].getStr())

proc updateLockFile(moduleName: string, repoUrl: string) =
    const lockFile = "acid.lock"
    var lockData: JsonNode
    if fileExists(lockFile):
        lockData = parseJson(readFile(lockFile))
    else:
        lockData = newJObject()
    lockData[moduleName] = %*{
        "repo": repoUrl,
        "timestamp": getTime().format("yyyy-MM-dd'T'HH:mm:ss")
    }
    writeFile(lockFile, $lockData)

proc removeFromLockFile(moduleName: string) =
    const lockFile = "acid.lock"
    if not fileExists(lockFile):
        echo "No " & lockFile & " found."
        return

    var lockData = parseJson(readFile(lockFile))
    if not lockData.hasKey(moduleName):
        echo &"Module {moduleName} not found in lock file."
        return

    lockData.delete(moduleName)
    writeFile(lockFile, $lockData)
    echo &"Removed {moduleName} from lock file."

proc deleteModule(moduleName: string) =
    const lockFile = "acid.lock"
    var found = false
    var targetDir = ""

    if fileExists(lockFile):
        let lockData = parseJson(readFile(lockFile))
        if lockData.hasKey(moduleName):
            found = true
            let pkgDir = "pkg"
            if dirExists(pkgDir):
                for kind, path in walkDir(pkgDir):
                    if kind == pcDir:
                        let dirName = path.splitPath().tail
                        if dirName.startsWith(moduleName & "_"):
                            targetDir = path
                            break

    if not found:
        let pkgDir = "pkg"
        if dirExists(pkgDir):
            for kind, path in walkDir(pkgDir):
                if kind == pcDir:
                    let dirName = path.splitPath().tail
                    if dirName.startsWith(moduleName & "_"):
                        targetDir = path
                        found = true
                        break

    if not found:
        echo &"Module {moduleName} not found."
        quit(1)

    if targetDir != "" and dirExists(targetDir):
        removeDir(targetDir)
        echo &"Removed module directory {targetDir}"

    removeFromLockFile(moduleName)

proc restoreFromLockFile() =
    const lockFile = "acid.lock"
    if not fileExists(lockFile):
        echo "No " & lockFile & " found."
        quit(1)

    let lockData = parseJson(readFile(lockFile))
    for moduleName in lockData.keys:
        let repoUrl = lockData[moduleName]["repo"].getStr()
        let repoName = repoUrl.split("/")[^1].replace(".git", "")
        let cloneDir = "tmp_" & repoName

        echo &"Restoring {moduleName} from {repoUrl}"
        discard runShell(&"git clone --depth 1 {repoUrl} {cloneDir}")

        let moduleFile = cloneDir / "module.acidcfg"
        if not fileExists(moduleFile):
            echo "No module.acidcfg found for {moduleName}, skipping."
            removeDir(cloneDir)
            continue

        let (parsedName, author) = parseModule(moduleFile)
        let authorHash = sha1Hash(author)
        let targetDir = &"pkg/{parsedName}_{authorHash}"

        if dirExists(targetDir):
            removeDir(targetDir)
        createDir(targetDir)
        moveDir(cloneDir, targetDir)

        echo &"Restored {parsedName} to {targetDir}"

proc initModuleFile() =
    let cwd = getCurrentDir().splitPath().tail
    let projName = cwd.replace(" ", "_").toLowerAscii()
    let author = getEnv("USER", getEnv("USERNAME", "unknown"))
    let content = %*{
        "name": projName,
        "author": author
    }
    let filePath = "module.acidcfg"

    if fileExists(filePath):
        echo "module.acidcfg already exists. Aborting."
        quit(1)

    writeFile(filePath, $content)
    echo &"Initialized module."

when isMainModule:
    var p = initOptParser()
    var inputUrl: string
    var restoreMode = false
    var initMode = false
    var deleteModule_name: string

    for kind, key, val in p.getopt():
        if kind == cmdArgument:
            if key == "init":
                initMode = true
            elif key == "restore":
                restoreMode = true
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

    if inputUrl.len == 0:
        echo """
ACE (v0.0.1) - Acid Code Exchange - A package manager for Acid

Usage: ace <options>=<params>
    
    -i=<git-repo-link>  : Install a package
    -r=<module-name>    : Remove a package

    restore             : Restore all packages from lockfile
    init                : Initialise module.acidcfg
    
Note: Installing a package that is already installed in the current acid module will update it to the
corresponding git repositories HEAD."""
        quit(1)

    if findExe("git") == "":
        echo "Error: Git is not installed or not in PATH. Install Git."
        quit(1)

    let repoName = inputUrl.split("/")[^1].replace(".git", "")
    let cloneDir = "tmp_" & repoName

    echo "Cloning..."
    discard runShell(&"git clone --depth 1 {inputUrl} {cloneDir}")

    let moduleFile = cloneDir / "module.acidcfg"
    if not fileExists(moduleFile):
        echo "No module.acidcfg file found."
        removeDir(cloneDir)
        quit(1)

    let (moduleName, author) = parseModule(moduleFile)
    let authorHash = sha1Hash(author)
    let targetDir = &"pkg/{moduleName}_{authorHash}"

    if dirExists(targetDir):
        removeDir(targetDir)

    createDir(targetDir)
    moveDir(cloneDir, targetDir)
    echo &"Saved module to {targetDir}"
    updateLockFile(moduleName, inputUrl)
    echo "Lockfile updated."
