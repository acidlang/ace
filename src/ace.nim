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
    lockData[moduleName] = %*{"repo": repoUrl, "timestamp": getTime().format("yyyy-MM-dd'T'HH:mm:ss")}
    writeFile(lockFile, $lockData)

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

when isMainModule:
    var p = initOptParser()
    var inputUrl: string
    var restoreMode = false

    for kind, key, val in p.getopt():
        if kind == cmdArgument:
            discard
        elif kind == cmdShortOption:
            if key == "i":
                inputUrl = val
            elif key == "r":
                restoreMode = true
        elif kind == cmdEnd:
            break

    if restoreMode:
        restoreFromLockFile()
        quit(0)

    if inputUrl.len == 0:
        echo "Usage: ace <options>=<params>\n\t-i=<git-repo-link> " &
            ": Install some package\n\t-r : Restore all packages from lockfile "
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
