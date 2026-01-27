// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
)

// stopBooth stops a running booth container.
// Usage: coding-booth stop [--name <name>] [--force] [--time <seconds>]
func stopBooth(version string) {
	fmt.Fprintln(os.Stderr, "Error: 'stop' command not yet implemented")
	fmt.Fprintln(os.Stderr, "This will stop a running booth container.")
	os.Exit(1)
}
