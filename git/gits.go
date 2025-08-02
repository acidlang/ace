package git

import (
	"fmt"
	"strings"

	"github.com/acidlang/ace/cmds"
)

func GetGitCommitHash(repoPath string) string {
	output, err := cmds.RunCommandOutput("git rev-parse HEAD", repoPath)
	if err != nil {
		return ""
	}
	return output
}

func GetGitTags(repoPath string) []string {
	output, err := cmds.RunCommandOutput("git tag --points-at HEAD", repoPath)
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

func GetGitCurrentBranch(repoPath string) string {
	output, err := cmds.RunCommandOutput("git branch --show-current", repoPath)
	if err != nil {
		return ""
	}
	return output
}

func GetLatestCommitHash(repoURL string) string {
	output, err := cmds.RunCommandOutput(fmt.Sprintf("git ls-remote %s HEAD", repoURL), "")
	if err != nil || output == "" {
		return ""
	}

	parts := strings.Split(output, "\t")
	if len(parts) > 0 {
		return strings.TrimSpace(parts[0])
	}
	return ""
}
