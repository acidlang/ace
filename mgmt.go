package main

import (
	"fmt"
)

const version = "v0.1.1"

func printUsage() {
	fmt.Printf("ACE (%s) - Acid Code Exchange - A package manager for Acid\n", version)
	fmt.Println(`
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
    ace -i=https://github.com/user/repo@abc123  # Install specific commit`)
	fmt.Println("\n\033[90mNote: Installing a package that is already installed will update it to the specified version or HEAD.\033[0m")
}
