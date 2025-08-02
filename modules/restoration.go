package modules

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/acidlang/ace/cmds"
	"github.com/acidlang/ace/lock"
)

func RestoreFromLockFile() {
	lockFile, err := lock.ParseLockFile("acid.lock")
	if err != nil {
		fmt.Println("No acid.lock found.")
		os.Exit(1)
	}

	for moduleName, entry := range lockFile {
		var (
			repoURL          = entry.Repo
			commitHash       = entry.CommitHash
			requestedVersion = entry.RequestedVersion
			parts            = strings.Split(repoURL, "/")
			repoName         = strings.TrimSuffix(parts[len(parts)-1], ".git")
			cloneDir         = "tmp_" + repoName
		)

		fmt.Printf("Restoring %s from %s\n", moduleName, repoURL)

		if commitHash != "" && len(commitHash) >= 7 {
			fmt.Printf("  Target commit: %s\n", commitHash[:7])
			if requestedVersion != "" {
				fmt.Printf("  Original version: %s\n", requestedVersion)
			}
		}

		err := cmds.RunCommand(fmt.Sprintf("git clone %s %s", repoURL, cloneDir))
		if err != nil {
			fmt.Printf("Error cloning %s: %v\n", repoURL, err)
			continue
		}

		if commitHash != "" {
			cwd, _ := os.Getwd()
			os.Chdir(cloneDir)
			err := cmds.RunCommand(fmt.Sprintf("git checkout %s", commitHash))
			os.Chdir(cwd)

			if err != nil {
				fmt.Printf("Warning: Could not checkout commit %s for %s\n", commitHash, moduleName)
			}
		}

		moduleFile := filepath.Join(cloneDir, "module.acidcfg")
		if _, err := os.Stat(moduleFile); err != nil {
			fmt.Printf("No module.acidcfg found for %s, skipping.\n", moduleName)
			os.RemoveAll(cloneDir)
			continue
		}

		config, err := ParseModuleConfig(moduleFile)
		if err != nil {
			fmt.Printf("Error parsing module config for %s: %v\n", moduleName, err)
			os.RemoveAll(cloneDir)
			continue
		}

		targetDir := filepath.Join("pkg", config.Name)

		if _, err := os.Stat(targetDir); err == nil {
			os.RemoveAll(targetDir)
		}

		os.MkdirAll(filepath.Dir(targetDir), 0755)
		err = os.Rename(cloneDir, targetDir)
		if err != nil {
			fmt.Printf("Error moving %s to %s: %v\n", cloneDir, targetDir, err)
			continue
		}

		fmt.Printf("Restored %s to %s\n", config.Name, targetDir)
	}
}
