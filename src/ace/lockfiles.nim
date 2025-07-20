import
    os,
    strutils,
    strformat,
    times,
    json,
    ops,
    modules

proc updateLockFile*(
    moduleName: string,
    repoUrl: string,
    commitHash: string = "",
    requestedVersion: string = "",
    tags: seq[string] = @[],
    branch: string = ""
) =
    ## Update acid.lock with git versioning information
    const lockFile = "acid.lock"
    var lockData: JsonNode

    if fileExists(lockFile):
        lockData = parseJson(readFile(lockFile))
    else:
        lockData = newJObject()

    var moduleEntry = %*{
        "repo": repoUrl,
        "timestamp": getTime().format("yyyy-MM-dd'T'HH:mm:ss"),
        "commit_hash": commitHash,
        "requested_version": requestedVersion,
        "branch": branch
    }

    if tags.len > 0:
        moduleEntry["tags"] = %tags

    lockData[moduleName] = moduleEntry
    writeFile(lockFile, lockData.pretty())

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
    writeFile(lockFile, lockData.pretty())
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
                if dirName == moduleName:
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
    ## Restore packages to pkg directory from the lockfile with exact versions.
    const lockFile = "acid.lock"
    if not fileExists(lockFile):
        echo "No " & lockFile & " found."
        quit(1)

    let lockData = parseJson(readFile(lockFile))
    for moduleName in lockData.keys:
        let entry = lockData[moduleName]
        let repoUrl = entry["repo"].getStr()
        let commitHash = entry.getOrDefault("commit_hash").getStr()
        let requestedVersion = entry.getOrDefault("requested_version").getStr()
        let repoName = repoUrl.split("/")[^1].replace(".git", "")
        let cloneDir = "tmp_" & repoName

        echo &"Restoring {moduleName} from {repoUrl}"

        if commitHash.len > 0:
            echo &"  Target commit: {commitHash[0..7]}"
            if requestedVersion.len > 0:
                echo &"  Original version: {requestedVersion}"

        run(&"git clone {repoUrl} {cloneDir}")

        if commitHash.len > 0:
            let currentDir = getCurrentDir()
            setCurrentDir(cloneDir)
            let checkoutResult = execShellCmd(&"git checkout {commitHash}")
            setCurrentDir(currentDir)

            if checkoutResult != 0:
                echo &"Warning: Could not checkout commit {commitHash} for {moduleName}"

        let moduleFile = cloneDir / "module.acidcfg"
        if not fileExists(moduleFile):
            echo &"No module.acidcfg found for {moduleName}, skipping."
            removeDir(cloneDir)
            continue

        let (parsedName, _) = parseModule(moduleFile)
        let targetDir = &"pkg/{parsedName}"

        if dirExists(targetDir):
            removeDir(targetDir)

        createDir(targetDir)
        moveDir(cloneDir, targetDir)
        echo &"Restored {parsedName} to {targetDir}"

proc upgradeAllModules*() =
    ## Upgrade all modules to their latest versions
    const lockFile = "acid.lock"
    if not fileExists(lockFile):
        echo "No " & lockFile & " found."
        quit(1)

    let lockData = parseJson(readFile(lockFile))
    if lockData.len == 0:
        echo "No modules to upgrade."
        return

    echo "Upgrading all modules to latest versions..."

    for moduleName in lockData.keys:
        let entry = lockData[moduleName]
        let repoUrl = entry["repo"].getStr()
        let currentHash = entry.getOrDefault("commit_hash").getStr()

        echo &"Checking {moduleName}..."

        let latestHash = getLatestCommitHash(repoUrl)

        if latestHash.len > 0 and latestHash != currentHash:
            echo &"  Updating from {currentHash[0..7]} to {latestHash[0..7]}"

            let repoName = repoUrl.split("/")[^1].replace(".git", "")
            let cloneDir = "tmp_" & repoName
            run(&"git clone --depth 1 {repoUrl} {cloneDir}")

            let moduleFile = cloneDir / "module.acidcfg"
            if not fileExists(moduleFile):
                echo &"  Warning: No module.acidcfg found, skipping {moduleName}"
                removeDir(cloneDir)
                continue

            let targetDir = &"pkg/{moduleName}"
            if dirExists(targetDir):
                removeDir(targetDir)

            createDir(targetDir)
            moveDir(cloneDir, targetDir)

            let currentDir = getCurrentDir()
            setCurrentDir(targetDir)
            let newCommitHash = getGitCommitHash(".")
            let newTags = getGitTags(".")
            let newBranch = getGitCurrentBranch(".")
            setCurrentDir(currentDir)

            updateLockFile(moduleName, repoUrl, newCommitHash, "", newTags, newBranch)
            echo &"  Updated {moduleName}"
        else:
            echo &"  {moduleName} is already up to date"
