// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/booth"
	"github.com/nawaman/codingbooth/src/pkg/docker"
)

// removeBooth removes a stopped booth container.
// Usage: coding-booth remove [--name <name>] [--force] [container...]
func removeBooth(version string) {
	var (
		containerName string
		force         bool
		verbose       bool
	)

	args := os.Args[2:] // Skip "coding-booth remove"
	var positionalArgs []string

	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--name":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --name requires a value")
				os.Exit(1)
			}
			i++
			containerName = args[i]
		case "-f", "--force":
			force = true
		case "--verbose":
			verbose = true
		case "-h", "--help":
			showRemoveHelp()
			return
		default:
			if strings.HasPrefix(args[i], "-") {
				fmt.Fprintf(os.Stderr, "Unknown option: %s\n", args[i])
				fmt.Fprintln(os.Stderr, "Use 'coding-booth remove --help' for usage information")
				os.Exit(1)
			}
			positionalArgs = append(positionalArgs, args[i])
		}
	}

	flags := docker.DockerFlags{
		Dryrun:  false,
		Verbose: verbose,
		Silent:  false,
	}

	// Build list of containers to remove
	var containers []string

	if containerName != "" {
		containers = append(containers, containerName)
	}
	containers = append(containers, positionalArgs...)

	// If no containers specified, infer from current directory
	if len(containers) == 0 {
		cwd, err := os.Getwd()
		if err != nil {
			fmt.Fprintln(os.Stderr, "Error: Cannot determine current directory")
			os.Exit(1)
		}
		containers = append(containers, sanitizeName(filepath.Base(cwd)))
	}

	// Remove each container
	hasError := false
	for _, name := range containers {
		// Verify container exists and is managed by booth
		inspect, err := docker.InspectContainer(name, flags)
		if err != nil {
			if strings.Contains(err.Error(), "No such") {
				fmt.Fprintf(os.Stderr, "Error: No booth '%s' found.\n", name)
				hasError = true
				continue
			}
			fmt.Fprintf(os.Stderr, "Error inspecting container '%s': %v\n", name, err)
			hasError = true
			continue
		}

		if inspect.Labels[booth.LabelManaged] != "true" {
			fmt.Fprintf(os.Stderr, "Error: Container '%s' is not managed by CodingBooth.\n", name)
			hasError = true
			continue
		}

		// Check if container is running
		if inspect.State.Running && !force {
			fmt.Fprintf(os.Stderr, "Error: Container '%s' is running. Use --force to remove it.\n", name)
			hasError = true
			continue
		}

		// Remove the container
		fmt.Printf("Removing booth '%s'...\n", name)

		err = docker.RemoveContainer(name, force, flags)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error removing container '%s': %v\n", name, err)
			hasError = true
			continue
		}

		fmt.Printf("Booth '%s' removed.\n", name)
	}

	if hasError {
		os.Exit(1)
	}
}

func showRemoveHelp() {
	fmt.Println(`Usage: coding-booth remove [OPTIONS] [CONTAINER...]

Remove stopped booth containers.

OPTIONS:
  --name <name>    Container name to remove
  -f, --force      Force remove even if running
  --verbose        Show verbose output
  -h, --help       Show this help

If no names are provided, the container name is inferred from
the current directory name.

Multiple containers can be removed at once by listing them.

EXAMPLES:
  coding-booth remove                  # Remove booth for current directory
  coding-booth remove my-project       # Remove booth by name
  coding-booth remove proj1 proj2      # Remove multiple booths
  coding-booth remove --force          # Force remove even if running`)
}
