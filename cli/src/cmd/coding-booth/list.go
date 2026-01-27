// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
)

// listBooths shows all booth-managed containers.
// Usage: coding-booth list [--running] [--stopped] [--quiet]
func listBooths(version string) {
	fmt.Fprintln(os.Stderr, "Error: 'list' command not yet implemented")
	fmt.Fprintln(os.Stderr, "This will show all booth-managed containers.")
	os.Exit(1)
}
