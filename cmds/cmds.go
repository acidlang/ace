package cmds

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

func RunCommand(command string) error {
	parts := strings.Fields(command)
	if len(parts) == 0 {
		return fmt.Errorf("empty command")
	}

	cmd := exec.Command(parts[0], parts[1:]...)
	return cmd.Run()
}

func RunCommandQuiet(command string) error {
	parts := strings.Fields(command)
	if len(parts) == 0 {
		return fmt.Errorf("empty command")
	}

	cmd := exec.Command(parts[0], parts[1:]...)
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run()
}

func RunCommandOutput(command string, workingDir string) (string, error) {
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

func FileExists(filename string) bool {
	_, err := os.Stat(filename)
	return err == nil
}

func CommandExists(cmd string) bool {
	_, err := exec.LookPath(cmd)
	return err == nil
}
