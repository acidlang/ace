import
    os,
    strutils,
    strformat,
    json

proc parseModule*(file: string): (string, string) =
    ## Extract module name and author from module.acidcfg
    ## (format: JSON with name and author fields)
    let content = readFile(file)
    let data = parseJson(content)
    result = (data["name"].getStr(), data["author"].getStr())

proc initModuleFile*() =
    ## Initialise the module (acidcfg creation occurs here).
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

proc listModules*() =
    const lockFile = "acid.lock"
    if not fileExists(lockFile):
        echo "No acid.lock file found."
        quit(1)

    let lockData = parseJson(readFile(lockFile))
    if lockData.len == 0:
        echo "No modules installed."
        return

    echo "Installed Modules:"
    for key in lockData.keys:
        let entry = lockData[key]
        let repo = entry["repo"].getStr();
        let timestamp = entry["timestamp"].getStr();
        echo &"- {key} @ {repo} (installed {timestamp})"

proc showModuleInfo*(moduleName: string) =
    ## Show detailed info about a single module.
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
    echo &"Module: {moduleName}"
    echo &"Repository: {repo}"
    echo &"Installed At: {tstamp}"

    let moduleCfg = &"pkg/{moduleName}/module.acidcfg"
    if fileExists(moduleCfg):
        let content = parseJson(readFile(moduleCfg))
        if content.hasKey("author"):
            let author = content["author"].getStr()
            echo &"Author: {author}"
        if content.hasKey("version"):
            let version = content["version"].getStr()
            echo &"Version: {version}"
    else:
        echo "Warning: module.acidcfg not found in pkg/"
