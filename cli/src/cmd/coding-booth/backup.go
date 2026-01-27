// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
)

// backupImage saves an image to a tar file.
// Usage: coding-booth backup <image> --output <file> [--compress]
func backupImage(version string) {
	fmt.Fprintln(os.Stderr, "Error: 'backup' command not yet implemented")
	fmt.Fprintln(os.Stderr, "This will save a Docker image to a tar file.")
	os.Exit(1)
}
