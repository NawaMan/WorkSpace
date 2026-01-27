// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
)

// startBooth starts an existing stopped booth container.
// Usage: coding-booth start [--name <name>] [--code <path>] [--daemon]
func startBooth(version string) {
	fmt.Fprintln(os.Stderr, "Error: 'start' command not yet implemented")
	fmt.Fprintln(os.Stderr, "This will start a stopped booth container.")
	os.Exit(1)
}
