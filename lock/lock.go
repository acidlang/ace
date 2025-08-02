package lock

import (
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/acidlang/ace/texts"
)

type LockEntry struct {
	Repo             string   `json:"repo"`
	Timestamp        string   `json:"timestamp"`
	CommitHash       string   `json:"commit_hash"`
	RequestedVersion string   `json:"requested_version"`
	Branch           string   `json:"branch"`
	Tags             []string `json:"tags"`
}

type LockFile map[string]LockEntry

// Parse some lockfile given the filename.
//
// Returns the lockfile instance.
func ParseLockFile(filename string) (LockFile, error) {
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

	fieldNames := map[string]bool{
		"repo":              true,
		"timestamp":         true,
		"commit_hash":       true,
		"requested_version": true,
		"branch":            true,
		"tags":              true,
	}

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || line == "{" || line == "}" {
			continue
		}

		if strings.Contains(line, "\":") {
			fieldName := texts.ExtractString(line, "\"", "\":")

			if !fieldNames[fieldName] {
				if currentModule != "" {
					lockFile[currentModule] = currentEntry
				}
				currentModule = fieldName
				currentEntry = LockEntry{}
			} else {
				switch fieldName {
				case "repo":
					currentEntry.Repo = texts.ExtractString(line, "\"repo\": \"", "\"")
				case "timestamp":
					currentEntry.Timestamp = texts.ExtractString(line, "\"timestamp\": \"", "\"")
				case "commit_hash":
					currentEntry.CommitHash = texts.ExtractString(line, "\"commit_hash\": \"", "\"")
				case "requested_version":
					currentEntry.RequestedVersion = texts.ExtractString(line, "\"requested_version\": \"", "\"")
				case "branch":
					currentEntry.Branch = texts.ExtractString(line, "\"branch\": \"", "\"")
				case "tags":
					tagsStr := texts.ExtractString(line, "\"tags\": [", "]")
					if tagsStr != "" {
						tags := strings.Split(tagsStr, ",")
						for i, tag := range tags {
							tags[i] = strings.Trim(strings.TrimSpace(tag), "\"")
						}
						currentEntry.Tags = tags
					}
				}
			}
		}
	}

	if currentModule != "" {
		lockFile[currentModule] = currentEntry
	}

	return lockFile, nil
}

// Write to the lockfile given the filename and the lockfile instance,
// (Not a pointer to it, the instance copy itself).
func WriteLockFile(filename string, lockFile LockFile) error {
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

func UpdateLockFile(moduleName, repoURL, commitHash, requestedVersion string, tags []string, branch string) error {
	lockFile, err := ParseLockFile("acid.lock")
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
	return WriteLockFile("acid.lock", lockFile)
}

func RemoveFromLockFile(moduleName string) error {
	lockFile, err := ParseLockFile("acid.lock")
	if err != nil {
		fmt.Println("No acid.lock found.")
		return err
	}

	if _, exists := lockFile[moduleName]; !exists {
		fmt.Printf("Module %s not found in lock file.\n", moduleName)
		return fmt.Errorf("module not found")
	}

	delete(lockFile, moduleName)
	err = WriteLockFile("acid.lock", lockFile)
	if err == nil {
		fmt.Printf("Removed %s from lock file.\n", moduleName)
	}
	return err
}
