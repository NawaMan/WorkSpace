// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
)

// commitBooth creates a Docker image from a container's current state.
// Usage: coding-booth commit --tag <tag> [--name <name>] [--message <msg>]
func commitBooth(version string) {
	fmt.Fprintln(os.Stderr, "Error: 'commit' command not yet implemented")
	fmt.Fprintln(os.Stderr, "This will save a booth container as a Docker image.")
	os.Exit(1)
}
