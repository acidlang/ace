package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/acidlang/ace/cmds"
	"github.com/acidlang/ace/git"
	"github.com/acidlang/ace/lock"
	"github.com/acidlang/ace/modules"
)

func main() {
	var (
		args             = os.Args[1:]
		inputURL         string
		targetVersion    string
		restoreMode      bool
		initMode         bool
		listMode         bool
		infoMode         bool
		versionMode      bool
		upgradeMode      bool
		deleteModuleName string
		infoModuleName   string
	)

	for i, arg := range args {
		if arg == "init" {
			initMode = true
		} else if arg == "restore" {
			restoreMode = true
		} else if arg == "version" {
			versionMode = true
		} else if arg == "list" {
			listMode = true
		} else if arg == "info" {
			infoMode = true
			if i+1 < len(args) {
				infoModuleName = args[i+1]
			}
		} else if arg == "upgrade" {
			upgradeMode = true
		} else if strings.HasPrefix(arg, "-i=") {
			val := arg[3:]
			if strings.Contains(val, "@") {
				parts := strings.SplitN(val, "@", 2)
				inputURL = parts[0]
				targetVersion = parts[1]
			} else {
				inputURL = val
			}
		} else if strings.HasPrefix(arg, "-r=") {
			deleteModuleName = arg[3:]
		} else if strings.HasPrefix(arg, "-v=") {
			targetVersion = arg[3:]
		}
	}

	if versionMode {
		fmt.Println(version)
		os.Exit(0)
	}

	if initMode {
		modules.InitModuleFile()
		os.Exit(0)
	}

	if restoreMode {
		modules.RestoreFromLockFile()
		os.Exit(0)
	}

	if upgradeMode {
		modules.UpgradeAllModules()
		os.Exit(0)
	}

	if deleteModuleName != "" {
		modules.DeleteModule(deleteModuleName)
		os.Exit(0)
	}

	if listMode {
		modules.ListModules()
		os.Exit(0)
	}

	if infoMode && infoModuleName != "" {
		modules.ShowModuleInfo(infoModuleName)
		os.Exit(0)
	}

	if inputURL == "" {
		printUsage()
		os.Exit(1)
	}

	if !cmds.CommandExists("git") {
		fmt.Println("Error: Git is not installed or not in PATH. Install Git.")
		os.Exit(1)
	}

	var (
		parts    = strings.Split(inputURL, "/")
		repoName = strings.TrimSuffix(parts[len(parts)-1], ".git")
		cloneDir = "tmp_" + repoName
	)

	fmt.Println("Cloning...")

	var commitHash string
	if targetVersion != "" {
		err := cmds.RunCommandQuiet(fmt.Sprintf("git clone %s %s", inputURL, cloneDir))
		if err != nil {
			fmt.Printf("Error cloning repository: %v\n", err)
			os.Exit(1)
		}

		cwd, _ := os.Getwd()
		os.Chdir(cloneDir)
		err = cmds.RunCommand(fmt.Sprintf("git checkout %s", targetVersion))
		if err != nil {
			fmt.Printf("Error: Could not checkout version '%s'\n", targetVersion)
			os.Chdir(cwd)
			os.RemoveAll(cloneDir)
			os.Exit(1)
		}

		commitHash = git.GetGitCommitHash(".")
		os.Chdir(cwd)

		if len(commitHash) >= 8 {
			fmt.Printf("Checked out version %s (commit: %s)\n", targetVersion, commitHash[:7])
		}
	} else {
		err := cmds.RunCommandQuiet(fmt.Sprintf("git clone --depth 1 %s %s", inputURL, cloneDir))
		if err != nil {
			fmt.Printf("Error cloning repository: %v\n", err)
			os.Exit(1)
		}
	}

	moduleFile := filepath.Join(cloneDir, "module.acidcfg")
	if !cmds.FileExists(moduleFile) {
		fmt.Println("No module.acidcfg file found.")
		os.RemoveAll(cloneDir)
		os.Exit(1)
	}

	config, err := modules.ParseModuleConfig(moduleFile)
	if err != nil {
		fmt.Printf("Error parsing module config: %v\n", err)
		os.RemoveAll(cloneDir)
		os.Exit(1)
	}

	targetDir := filepath.Join("pkg", config.Name)

	cwd, _ := os.Getwd()
	os.Chdir(cloneDir)
	if commitHash == "" {
		commitHash = git.GetGitCommitHash(".")
	}
	gitTags := git.GetGitTags(".")
	currentBranch := git.GetGitCurrentBranch(".")
	os.Chdir(cwd)

	if _, err := os.Stat(targetDir); err == nil {
		os.RemoveAll(targetDir)
	}

	os.MkdirAll(filepath.Dir(targetDir), 0755)
	err = os.Rename(cloneDir, targetDir)
	if err != nil {
		fmt.Printf("Error moving directory: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Saved module to %s\n", targetDir)

	err = lock.UpdateLockFile(config.Name, inputURL, commitHash, targetVersion, gitTags, currentBranch)
	if err != nil {
		fmt.Printf("Error updating lockfile: %v\n", err)
	} else {
		fmt.Println("Lockfile updated with version information.")
	}
}
