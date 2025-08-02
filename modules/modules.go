package modules

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/acidlang/ace/cmds"
	"github.com/acidlang/ace/git"
	"github.com/acidlang/ace/lock"
	"github.com/acidlang/ace/texts"
)

// A module configuration, containing name, author and version.
type ModuleConfig struct {
	Name    string `json:"name"`
	Author  string `json:"author"`
	Version string `json:"version"`
}

// Parse the module configuration from a file and get back the object.
func ParseModuleConfig(filename string) (ModuleConfig, error) {
	var config ModuleConfig

	file, err := os.Open(filename)
	if err != nil {
		return config, err
	}
	defer file.Close()

	content, err := io.ReadAll(file)
	if err != nil {
		return config, err
	}

	lines := strings.SplitSeq(string(content), "\n")
	for line := range lines {
		line = strings.TrimSpace(line)
		if strings.Contains(line, "\"name\":") {
			config.Name = texts.ExtractString(line, "\"name\": \"", "\"")
		} else if strings.Contains(line, "\"author\":") {
			config.Author = texts.ExtractString(line, "\"author\": \"", "\"")
		} else if strings.Contains(line, "\"version\":") {
			config.Version = texts.ExtractString(line, "\"version\": \"", "\"")
		}
	}

	return config, nil
}

// Write the module configuration to disk.
func WriteModuleConfig(filename string, config ModuleConfig) error {
	file, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer file.Close()

	file.WriteString("{\n")
	fmt.Fprintf(file, "  \"name\": \"%s\",\n", config.Name)
	fmt.Fprintf(file, "  \"author\": \"%s\",\n", config.Author)
	fmt.Fprintf(file, "  \"version\": \"%s\"\n", config.Version)
	file.WriteString("}\n")

	return nil
}

func InitModuleFile() {
	cwd, err := os.Getwd()
	if err != nil {
		fmt.Println("Error getting current directory")
		os.Exit(1)
	}

	projName := strings.ToLower(strings.ReplaceAll(filepath.Base(cwd), " ", "_"))
	author := os.Getenv("USER")
	if author == "" {
		author = os.Getenv("USERNAME")
	}
	if author == "" {
		author = "unknown"
	}

	config := ModuleConfig{
		Name:    projName,
		Author:  author,
		Version: "0.1.0",
	}

	if _, err := os.Stat("module.acidcfg"); err == nil {
		fmt.Println("module.acidcfg already exists. Aborting.")
		os.Exit(1)
	}

	err = WriteModuleConfig("module.acidcfg", config)
	if err != nil {
		fmt.Printf("Error writing module.acidcfg: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("Initialized module.")
}

func ListModules() {
	lockFile, err := lock.ParseLockFile("acid.lock")
	if err != nil {
		fmt.Println("No acid.lock file found.")
		os.Exit(1)
	}

	if len(lockFile) == 0 {
		fmt.Println("No modules installed.")
		return
	}

	for moduleName, entry := range lockFile {
		versionInfo := ""
		if entry.RequestedVersion != "" {
			versionInfo = fmt.Sprintf(" (v%s)", entry.RequestedVersion)
		} else if entry.CommitHash != "" && len(entry.CommitHash) >= 7 {
			versionInfo = fmt.Sprintf(" (%s)", entry.CommitHash[:7])
		}

		fmt.Printf("- %s%s @ %s (installed %s)\n", moduleName, versionInfo, entry.Repo, entry.Timestamp)
	}
}

func ShowModuleInfo(moduleName string) {
	lockFile, err := lock.ParseLockFile("acid.lock")
	if err != nil {
		fmt.Println("No acid.lock file found.")
		os.Exit(1)
	}

	entry, exists := lockFile[moduleName]
	if !exists {
		fmt.Printf("Module '%s' not found in lock file.\n", moduleName)
		os.Exit(1)
	}

	fmt.Printf("Module: %s\n", moduleName)
	fmt.Printf("Repository: %s\n", entry.Repo)
	fmt.Printf("Installed At: %s\n", entry.Timestamp)

	if entry.RequestedVersion != "" {
		fmt.Printf("Requested Version: %s\n", entry.RequestedVersion)
	}

	if entry.CommitHash != "" {
		fmt.Printf("Commit Hash: %s\n", entry.CommitHash)
	}

	if entry.Branch != "" {
		fmt.Printf("Branch: %s\n", entry.Branch)
	}

	if len(entry.Tags) > 0 {
		fmt.Printf("Tags: %s\n", strings.Join(entry.Tags, ", "))
	}

	moduleCfg := filepath.Join("pkg", moduleName, "module.acidcfg")
	if _, err := os.Stat(moduleCfg); err == nil {
		config, err := ParseModuleConfig(moduleCfg)
		if err == nil {
			if config.Author != "" {
				fmt.Printf("Author: %s\n", config.Author)
			}
			if config.Version != "" {
				fmt.Printf("Module Version: %s\n", config.Version)
			}
		}
	} else {
		fmt.Println("Warning: module.acidcfg not found in pkg/ directory")
	}
}

func DeleteModule(moduleName string) {
	lockFile, err := lock.ParseLockFile("acid.lock")
	found := false
	targetDir := ""

	if err == nil {
		if _, exists := lockFile[moduleName]; exists {
			found = true
		}
	}

	pkgDir := "pkg"
	if _, err := os.Stat(pkgDir); err == nil {
		entries, err := os.ReadDir(pkgDir)
		if err == nil {
			for _, entry := range entries {
				if entry.IsDir() && entry.Name() == moduleName {
					targetDir = filepath.Join(pkgDir, entry.Name())
					found = true
					break
				}
			}
		}
	}

	if !found {
		fmt.Printf("Module %s not found.\n", moduleName)
		os.Exit(1)
	}

	if targetDir != "" {
		if err := os.RemoveAll(targetDir); err != nil {
			fmt.Printf("Error removing directory %s: %v\n", targetDir, err)
		} else {
			fmt.Printf("Removed module directory %s\n", targetDir)
		}
	}

	lock.RemoveFromLockFile(moduleName)
}

func UpgradeAllModules() {
	lockFile, err := lock.ParseLockFile("acid.lock")
	if err != nil {
		fmt.Println("No acid.lock found.")
		os.Exit(1)
	}

	if len(lockFile) == 0 {
		fmt.Println("No modules to upgrade.")
		return
	}

	fmt.Println("Upgrading all modules to latest versions...")

	for moduleName, entry := range lockFile {
		repoURL := entry.Repo
		currentHash := entry.CommitHash

		fmt.Printf("Checking %s...\n", moduleName)

		latestHash := git.GetLatestCommitHash(repoURL)

		if latestHash != "" && latestHash != currentHash {
			if len(currentHash) >= 7 && len(latestHash) >= 7 {
				fmt.Printf("  Updating from %s to %s\n", currentHash[:7], latestHash[:7])
			}

			parts := strings.Split(repoURL, "/")
			repoName := strings.TrimSuffix(parts[len(parts)-1], ".git")
			cloneDir := "tmp_" + repoName

			err := cmds.RunCommand(fmt.Sprintf("git clone --depth 1 %s %s", repoURL, cloneDir))
			if err != nil {
				fmt.Printf("  Error cloning %s: %v\n", repoURL, err)
				continue
			}

			moduleFile := filepath.Join(cloneDir, "module.acidcfg")
			if _, err := os.Stat(moduleFile); err != nil {
				fmt.Printf("  Warning: No module.acidcfg found, skipping %s\n", moduleName)
				os.RemoveAll(cloneDir)
				continue
			}

			targetDir := filepath.Join("pkg", moduleName)
			if _, err := os.Stat(targetDir); err == nil {
				os.RemoveAll(targetDir)
			}

			os.MkdirAll(filepath.Dir(targetDir), 0755)
			err = os.Rename(cloneDir, targetDir)
			if err != nil {
				fmt.Printf("  Error moving %s to %s: %v\n", cloneDir, targetDir, err)
				continue
			}

			cwd, _ := os.Getwd()
			os.Chdir(targetDir)
			newCommitHash := git.GetGitCommitHash(".")
			newTags := git.GetGitTags(".")
			newBranch := git.GetGitCurrentBranch(".")
			os.Chdir(cwd)
			lock.UpdateLockFile(moduleName, repoURL, newCommitHash, "", newTags, newBranch)
			fmt.Printf("  Updated %s\n", moduleName)
		} else {
			fmt.Printf("  %s is already up to date\n", moduleName)
		}
	}
}
