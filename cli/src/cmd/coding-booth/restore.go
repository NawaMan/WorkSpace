// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
)

// restoreImage loads an image from a tar file.
// Usage: coding-booth restore <file>
func restoreImage(version string) {
	fmt.Fprintln(os.Stderr, "Error: 'restore' command not yet implemented")
	fmt.Fprintln(os.Stderr, "This will load a Docker image from a tar file.")
	os.Exit(1)
}
