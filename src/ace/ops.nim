import
    os,
    strutils,
    strformat,
    osproc,
    sequtils

proc run*(command: string) =
    ## Execute a shell command and quit on failure
    let result = execShellCmd(command)
    if result != 0:
        echo &"Command failed: {command}"
        quit(1)

proc runQuiet*(command: string) =
    ## Execute a shell command quietly and quit on failure
    let quietCommand = when defined(windows):
        command & " >NUL 2>&1"
    else:
        command & " >/dev/null 2>&1"
    let result = execShellCmd(quietCommand)
    if result != 0:
        echo &"Command failed: {command}"
        quit(1)

proc getGitCommitHash*(repoPath: string): string =
    ## Get the current commit hash of a git repository
    let (output, exitCode) = execCmdEx("git rev-parse HEAD",
            workingDir = repoPath)
    if exitCode == 0:
        result = output.strip()
    else:
        result = ""

proc getGitTags*(repoPath: string): seq[string] =
    ## Get all tags pointing to the current commit
    let (output, exitCode) = execCmdEx("git tag --points-at HEAD",
            workingDir = repoPath)
    if exitCode == 0 and output.len > 0:
        result = output.strip().split('\n').filterIt(it.len > 0)
    else:
        result = @[]

proc getGitCurrentBranch*(repoPath: string): string =
    ## Get the current branch name
    let (output, exitCode) = execCmdEx("git branch --show-current",
            workingDir = repoPath)
    if exitCode == 0:
        result = output.strip()
    else:
        result = ""

proc getLatestCommitHash*(repoUrl: string): string =
    ## Get the latest commit hash from a remote repository
    let (output, exitCode) = execCmdEx(&"git ls-remote {repoUrl} HEAD")
    if exitCode == 0 and output.len > 0:
        result = output.split('\t')[0].strip()
    else:
        result = ""

proc getRemoteTags*(repoUrl: string): seq[string] =
    ## Get all tags from a remote repository
    let (output, exitCode) = execCmdEx(&"git ls-remote --tags {repoUrl}")
    if exitCode == 0 and output.len > 0:
        result = @[]
        for line in output.split('\n'):
            if line.len > 0 and not line.contains("^{}"):
                let parts = line.split('\t')
                if parts.len >= 2:
                    let tag = parts[1].replace("refs/tags/", "")
                    result.add(tag)
    else:
        result = @[]
