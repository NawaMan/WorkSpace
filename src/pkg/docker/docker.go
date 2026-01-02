// Package docker provides Docker CLI execution with verbose and dryrun support.
package docker

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/nawaman/workspace/src/pkg/appctx"
)

// Docker executes a docker command with the given subcommand and arguments.
// It respects the AppContext's Dryrun and Verbose settings.
//
// The function automatically handles TTY-related flags (-i, -t, -it):
//   - If stdin/stdout are not connected to a TTY, these flags are automatically removed
//   - This allows code to unconditionally use -it flags; they'll work in terminals
//     but won't cause errors in non-TTY environments (tests, CI/CD, etc.)
func Docker(ctx appctx.AppContext, subcommand string, args ...string) error {
	// Build command arguments
	cmdArgs := make([]string, 0, len(args)+1)
	cmdArgs = append(cmdArgs, subcommand)

	// Filter out TTY-related flags if no TTY is available
	hasTTY := HasInteractiveTTY()
	for i := 0; i < len(args); i++ {
		arg := args[i]

		// Skip standalone -i, -t, -it flags if no TTY
		// But keep -t when it's followed by a value (like -t imagename for docker build)
		if !hasTTY && (arg == "-i" || arg == "-it") {
			continue
		}

		// For -t, check if next arg exists and doesn't start with -
		// If it does, this is -t <value>, not the TTY flag
		if !hasTTY && arg == "-t" {
			// Check if there's a next argument and it doesn't look like a flag
			if i+1 < len(args) && !strings.HasPrefix(args[i+1], "-") {
				// This is -t <value>, keep both
				cmdArgs = append(cmdArgs, arg)
				i++
				cmdArgs = append(cmdArgs, args[i])
				continue
			}
			// This is standalone -t (TTY flag), skip it
			continue
		}

		cmdArgs = append(cmdArgs, arg)
	}

	// Print if verbose OR dry-run
	if ctx.Dryrun() || ctx.Verbose() {
		PrintCmd("docker", cmdArgs...)
	}

	// Execute unless dry-run
	if !ctx.Dryrun() {
		cmd := exec.Command("docker", cmdArgs...)

		// Set environment for Windows path compatibility
		cmd.Env = append(os.Environ(), "MSYS_NO_PATHCONV=1")

		// Forward stdout and stderr
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Stdin = os.Stdin

		// Run and propagate exit status
		if err := cmd.Run(); err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				return fmt.Errorf("docker %s failed with exit code %d", subcommand, exitErr.ExitCode())
			}
			return fmt.Errorf("docker %s failed: %w", subcommand, err)
		}
	}

	return nil
}
