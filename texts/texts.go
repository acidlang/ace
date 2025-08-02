package texts

import "strings"

// Extract a string given a start, end and superstring.
func ExtractString(line, start, end string) string {
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
