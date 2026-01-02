package docker

import (
	"fmt"
	"regexp"
	"strings"
)

// simpleArgPattern matches arguments that don't need quoting (alphanumeric + _./:-).
var simpleArgPattern = regexp.MustCompile(`^[A-Za-z0-9_./:-]+$`)

// PrintCmd formats and prints a command with proper shell escaping.
// Output format: each argument followed by a space, then a newline.
func PrintCmd(command string, args ...string) {
	// Print command with trailing space
	if simpleArgPattern.MatchString(command) {
		fmt.Printf("%s ", command)
	} else {
		fmt.Printf("%s ", escapeArg(command))
	}

	// Print each argument with trailing space
	for _, arg := range args {
		if simpleArgPattern.MatchString(arg) {
			fmt.Printf("%s ", arg)
		} else {
			fmt.Printf("%s ", escapeArg(arg))
		}
	}

	fmt.Printf("\n")
}

// escapeArg wraps an argument in single quotes and escapes any single quotes within it.
// Single quotes are escaped as '\” (end quote, escaped quote, start quote).
func escapeArg(arg string) string {
	// Replace ' with '\''
	escaped := strings.ReplaceAll(arg, "'", "'\\''")
	return fmt.Sprintf("'%s'", escaped)
}
