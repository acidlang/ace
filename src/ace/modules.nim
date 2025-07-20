import
    os,
    strutils,
    sequtils,
    strformat,
    json

proc parseModule*(file: string): (string, string) =
    ## Extract module name and author from module.acidcfg
    ## (format: JSON with name and author fields)
    let content = readFile(file)
    let data = parseJson(content)
    result = (data["name"].getStr(), data.getOrDefault("author").getStr("unknown"))

proc initModuleFile*() =
    ## Initialise the module (acidcfg creation occurs here).
    let cwd = getCurrentDir().splitPath().tail
    let projName = cwd.replace(" ", "_").toLowerAscii()
    let author = getEnv("USER", getEnv("USERNAME", "unknown"))

    let content = %*{
        "name": projName,
        "author": author,
        "version": "0.1.0"
    }

    let filePath = "module.acidcfg"
    if fileExists(filePath):
        echo "module.acidcfg already exists. Aborting."
        quit(1)

    writeFile(filePath, content.pretty())
    echo &"Initialized module."

proc listModules*() =
    ## Write the installed modules in current project to stdout stream.
    const lockFile = "acid.lock"
    if not fileExists(lockFile):
        echo "No acid.lock file found."
        quit(1)

    let lockData = parseJson(readFile(lockFile))
    if lockData.len == 0:
        echo "No modules installed."
        return

    for key in lockData.keys:
        let entry = lockData[key]
        let repo = entry["repo"].getStr()
        let timestamp = entry["timestamp"].getStr()
        let commitHash = entry.getOrDefault("commit_hash").getStr()
        let requestedVersion = entry.getOrDefault("requested_version").getStr()

        var versionInfo = ""
        if requestedVersion.len > 0:
            versionInfo = &" (v{requestedVersion})"
        elif commitHash.len > 0:
            versionInfo = &" ({commitHash[0..7]})"

        echo &"- {key}{versionInfo} @ {repo} (installed {timestamp})"

proc showModuleInfo*(moduleName: string) =
    ## Show detailed info about a single module including git version information.
    const lockFile = "acid.lock"
    if not fileExists(lockFile):
        echo "No acid.lock file found."
        quit(1)

    let lockData = parseJson(readFile(lockFile))
    if not lockData.hasKey(moduleName):
        echo &"Module '{moduleName}' not found in lock file."
        quit(1)

    let entry = lockData[moduleName]
    let repo = entry["repo"].getStr()
    let tstamp = entry["timestamp"].getStr()
    let commitHash = entry.getOrDefault("commit_hash").getStr()
    let requestedVersion = entry.getOrDefault("requested_version").getStr()
    let branch = entry.getOrDefault("branch").getStr()

    echo &"Module: {moduleName}"
    echo &"Repository: {repo}"
    echo &"Installed At: {tstamp}"

    if requestedVersion.len > 0:
        echo &"Requested Version: {requestedVersion}"

    if commitHash.len > 0:
        echo &"Commit Hash: {commitHash}"

    if branch.len > 0:
        echo &"Branch: {branch}"

    if entry.hasKey("tags"):
        let tags = entry["tags"]
        if tags.len > 0:
            echo "Tags: " & tags.elems.mapIt(it.getStr()).join(", ")

    let moduleCfg = &"pkg/{moduleName}/module.acidcfg"
    if fileExists(moduleCfg):
        let content = parseJson(readFile(moduleCfg))
        if content.hasKey("author"):
            let author = content["author"].getStr()
            echo &"Author: {author}"
        if content.hasKey("version"):
            let version = content["version"].getStr()
            echo &"Module Version: {version}"
    else:
        echo "Warning: module.acidcfg not found in pkg/ directory"
