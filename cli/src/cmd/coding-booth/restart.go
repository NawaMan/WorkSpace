// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
)

// restartBooth restarts a running booth container.
// Usage: coding-booth restart [--name <name>] [--time <seconds>]
func restartBooth(version string) {
	fmt.Fprintln(os.Stderr, "Error: 'restart' command not yet implemented")
	fmt.Fprintln(os.Stderr, "This will restart a booth container.")
	os.Exit(1)
}
