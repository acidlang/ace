package modules

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/acidlang/ace/lock"
)

func PrintDependencyGraph() error {
	lockFile, err := lock.ParseLockFile("acid.lock")
	if err != nil {
		return fmt.Errorf("no acid.lock found")
	}
	if len(lockFile) == 0 {
		return fmt.Errorf("no modules installed")
	}
	currentModule := getCurrentModuleName()
	fmt.Printf("* %s\n", currentModule)
	var i int
	for moduleName, entry := range lockFile {
		isLast := i == len(lockFile)-1
		prefix := "└──"
		if !isLast {
			prefix = "├──"
		}
		version := entry.RequestedVersion
		if version == "" && len(entry.CommitHash) >= 7 {
			version = entry.CommitHash[:7]
		}
		if version == "" {
			version = "latest"
		}
		fmt.Printf("%s - %s (%s)\n", prefix, moduleName, version)
		infoPrefix := "     "
		if !isLast {
			infoPrefix = "│   "
		}
		if entry.Branch != "" {
			fmt.Printf("%s branch: %s\n", infoPrefix, entry.Branch)
		}
		if len(entry.Tags) > 0 {
			fmt.Printf("%s tags: %s\n", infoPrefix, entry.Tags[0])
		}
		i++
	}
	return nil
}

func getCurrentModuleName() string {
	if config, err := ParseModuleConfig("module.acidcfg"); err == nil {
		return config.Name
	}
	if dir, err := os.Getwd(); err == nil {
		return filepath.Base(dir)
	}
	return "current-module"
}
