import
    os,
    strutils,
    strformat,
    times,
    json,
    ops,
    modules

proc updateLockFile*(moduleName: string, repoUrl: string) =
    ## Update the acid.lock
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
    ## Remove an entry from acid.lock
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

proc deleteModule*(moduleName: string) =
    ## Delete a module from the pkg storage directory.
    ## Also remove the lockfile entry.
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

proc restoreFromLockFile*() =
    ## Restore packages to pkg directory from the lockfile.
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
        run(&"git clone --depth 1 {repoUrl} {cloneDir}")

        let moduleFile = cloneDir / "module.acidcfg"
        if not fileExists(moduleFile):
            echo "No module.acidcfg found for {moduleName}, skipping."
            removeDir(cloneDir)
            continue

        let (parsedName, _) = parseModule(moduleFile)
        let targetDir = &"pkg/{parsedName}"

        if dirExists(targetDir):
            removeDir(targetDir)
        createDir(targetDir)
        moveDir(cloneDir, targetDir)

        echo &"Restored {parsedName} to {targetDir}"
