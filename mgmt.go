package main

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const version = "v0.1.1"

type LockEntry struct {
	Repo             string   `json:"repo"`
	Timestamp        string   `json:"timestamp"`
	CommitHash       string   `json:"commit_hash"`
	RequestedVersion string   `json:"requested_version"`
	Branch           string   `json:"branch"`
	Tags             []string `json:"tags"`
}

type LockFile map[string]LockEntry

func parseLockFile(filename string) (LockFile, error) {
	lockFile := make(LockFile)

	file, err := os.Open(filename)
	if err != nil {
		return lockFile, err
	}
	defer file.Close()

	content, err := io.ReadAll(file)
	if err != nil {
		return lockFile, err
	}

	lines := strings.Split(string(content), "\n")
	var currentModule string
	var currentEntry LockEntry

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || line == "{" || line == "}" {
			continue
		}

		if strings.Contains(line, "\":") && !strings.Contains(line, "\"repo\":") {
			if currentModule != "" {
				lockFile[currentModule] = currentEntry
			}
			currentModule = extractString(line, "\"", "\":")
			currentEntry = LockEntry{}
		} else if strings.Contains(line, "\"repo\":") {
			currentEntry.Repo = extractString(line, "\"repo\": \"", "\"")
		} else if strings.Contains(line, "\"timestamp\":") {
			currentEntry.Timestamp = extractString(line, "\"timestamp\": \"", "\"")
		} else if strings.Contains(line, "\"commit_hash\":") {
			currentEntry.CommitHash = extractString(line, "\"commit_hash\": \"", "\"")
		} else if strings.Contains(line, "\"requested_version\":") {
			currentEntry.RequestedVersion = extractString(line, "\"requested_version\": \"", "\"")
		} else if strings.Contains(line, "\"branch\":") {
			currentEntry.Branch = extractString(line, "\"branch\": \"", "\"")
		} else if strings.Contains(line, "\"tags\":") {
			tagsStr := extractString(line, "\"tags\": [", "]")
			if tagsStr != "" {
				tags := strings.Split(tagsStr, ",")
				for i, tag := range tags {
					tags[i] = strings.Trim(strings.TrimSpace(tag), "\"")
				}
				currentEntry.Tags = tags
			}
		}
	}

	if currentModule != "" {
		lockFile[currentModule] = currentEntry
	}

	return lockFile, nil
}

func extractString(line, start, end string) string {
	startIdx := strings.Index(line, start)
	if startIdx == -1 {
		return ""
	}
	startIdx += len(start)

	endIdx := strings.Index(line[startIdx:], end)
	if endIdx == -1 {
		return ""
	}

	return line[startIdx : startIdx+endIdx]
}

func writeLockFile(filename string, lockFile LockFile) error {
	file, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer file.Close()

	file.WriteString("{\n")
	i := 0
	for moduleName, entry := range lockFile {
		if i > 0 {
			file.WriteString(",\n")
		}
		fmt.Fprintf(file, "  \"%s\": {\n", moduleName)
		fmt.Fprintf(file, "    \"repo\": \"%s\",\n", entry.Repo)
		fmt.Fprintf(file, "    \"timestamp\": \"%s\",\n", entry.Timestamp)
		fmt.Fprintf(file, "    \"commit_hash\": \"%s\",\n", entry.CommitHash)
		fmt.Fprintf(file, "    \"requested_version\": \"%s\",\n", entry.RequestedVersion)
		fmt.Fprintf(file, "    \"branch\": \"%s\"", entry.Branch)

		if len(entry.Tags) > 0 {
			file.WriteString(",\n    \"tags\": [")
			for j, tag := range entry.Tags {
				if j > 0 {
					file.WriteString(", ")
				}
				file.WriteString(fmt.Sprintf("\"%s\"", tag))
			}
			file.WriteString("]")
		}

		file.WriteString("\n  }")
		i++
	}
	file.WriteString("\n}\n")

	return nil
}

type ModuleConfig struct {
	Name    string `json:"name"`
	Author  string `json:"author"`
	Version string `json:"version"`
}

func parseModuleConfig(filename string) (ModuleConfig, error) {
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
			config.Name = extractString(line, "\"name\": \"", "\"")
		} else if strings.Contains(line, "\"author\":") {
			config.Author = extractString(line, "\"author\": \"", "\"")
		} else if strings.Contains(line, "\"version\":") {
			config.Version = extractString(line, "\"version\": \"", "\"")
		}
	}

	return config, nil
}

func writeModuleConfig(filename string, config ModuleConfig) error {
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

func runCommand(command string) error {
	parts := strings.Fields(command)
	if len(parts) == 0 {
		return fmt.Errorf("empty command")
	}

	cmd := exec.Command(parts[0], parts[1:]...)
	return cmd.Run()
}

func runCommandQuiet(command string) error {
	parts := strings.Fields(command)
	if len(parts) == 0 {
		return fmt.Errorf("empty command")
	}

	cmd := exec.Command(parts[0], parts[1:]...)
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run()
}

func runCommandOutput(command string, workingDir string) (string, error) {
	parts := strings.Fields(command)
	if len(parts) == 0 {
		return "", fmt.Errorf("empty command")
	}

	cmd := exec.Command(parts[0], parts[1:]...)
	if workingDir != "" {
		cmd.Dir = workingDir
	}

	output, err := cmd.Output()
	return strings.TrimSpace(string(output)), err
}

func getGitCommitHash(repoPath string) string {
	output, err := runCommandOutput("git rev-parse HEAD", repoPath)
	if err != nil {
		return ""
	}
	return output
}

func getGitTags(repoPath string) []string {
	output, err := runCommandOutput("git tag --points-at HEAD", repoPath)
	if err != nil || output == "" {
		return []string{}
	}

	lines := strings.Split(output, "\n")
	var tags []string
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line != "" {
			tags = append(tags, line)
		}
	}
	return tags
}

func getGitCurrentBranch(repoPath string) string {
	output, err := runCommandOutput("git branch --show-current", repoPath)
	if err != nil {
		return ""
	}
	return output
}

func getLatestCommitHash(repoURL string) string {
	output, err := runCommandOutput(fmt.Sprintf("git ls-remote %s HEAD", repoURL), "")
	if err != nil || output == "" {
		return ""
	}

	parts := strings.Split(output, "\t")
	if len(parts) > 0 {
		return strings.TrimSpace(parts[0])
	}
	return ""
}

func updateLockFile(moduleName, repoURL, commitHash, requestedVersion string, tags []string, branch string) error {
	lockFile, err := parseLockFile("acid.lock")
	if err != nil {
		lockFile = make(LockFile)
	}

	entry := LockEntry{
		Repo:             repoURL,
		Timestamp:        time.Now().Format("2006-01-02T15:04:05"),
		CommitHash:       commitHash,
		RequestedVersion: requestedVersion,
		Branch:           branch,
		Tags:             tags,
	}

	lockFile[moduleName] = entry
	return writeLockFile("acid.lock", lockFile)
}

func removeFromLockFile(moduleName string) error {
	lockFile, err := parseLockFile("acid.lock")
	if err != nil {
		fmt.Println("No acid.lock found.")
		return err
	}

	if _, exists := lockFile[moduleName]; !exists {
		fmt.Printf("Module %s not found in lock file.\n", moduleName)
		return fmt.Errorf("module not found")
	}

	delete(lockFile, moduleName)
	err = writeLockFile("acid.lock", lockFile)
	if err == nil {
		fmt.Printf("Removed %s from lock file.\n", moduleName)
	}
	return err
}

func initModuleFile() {
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

	err = writeModuleConfig("module.acidcfg", config)
	if err != nil {
		fmt.Printf("Error writing module.acidcfg: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("Initialized module.")
}

func listModules() {
	lockFile, err := parseLockFile("acid.lock")
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

func showModuleInfo(moduleName string) {
	lockFile, err := parseLockFile("acid.lock")
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
		config, err := parseModuleConfig(moduleCfg)
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

func deleteModule(moduleName string) {
	lockFile, err := parseLockFile("acid.lock")
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

	removeFromLockFile(moduleName)
}

func restoreFromLockFile() {
	lockFile, err := parseLockFile("acid.lock")
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

		err := runCommand(fmt.Sprintf("git clone %s %s", repoURL, cloneDir))
		if err != nil {
			fmt.Printf("Error cloning %s: %v\n", repoURL, err)
			continue
		}

		if commitHash != "" {
			cwd, _ := os.Getwd()
			os.Chdir(cloneDir)
			err := runCommand(fmt.Sprintf("git checkout %s", commitHash))
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

		config, err := parseModuleConfig(moduleFile)
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

func upgradeAllModules() {
	lockFile, err := parseLockFile("acid.lock")
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

		latestHash := getLatestCommitHash(repoURL)

		if latestHash != "" && latestHash != currentHash {
			if len(currentHash) >= 7 && len(latestHash) >= 7 {
				fmt.Printf("  Updating from %s to %s\n", currentHash[:7], latestHash[:7])
			}

			parts := strings.Split(repoURL, "/")
			repoName := strings.TrimSuffix(parts[len(parts)-1], ".git")
			cloneDir := "tmp_" + repoName

			err := runCommand(fmt.Sprintf("git clone --depth 1 %s %s", repoURL, cloneDir))
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
			newCommitHash := getGitCommitHash(".")
			newTags := getGitTags(".")
			newBranch := getGitCurrentBranch(".")
			os.Chdir(cwd)

			updateLockFile(moduleName, repoURL, newCommitHash, "", newTags, newBranch)
			fmt.Printf("  Updated %s\n", moduleName)
		} else {
			fmt.Printf("  %s is already up to date\n", moduleName)
		}
	}
}

func fileExists(filename string) bool {
	_, err := os.Stat(filename)
	return err == nil
}

func commandExists(cmd string) bool {
	_, err := exec.LookPath(cmd)
	return err == nil
}

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
