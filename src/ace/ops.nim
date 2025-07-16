import osproc

proc run*(cmd: string) =
    ## Execute some process and discard the result.
    ## This exists to prevent the "discard" pattern repeating itself.
    discard execProcess(cmd)
