// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/booth"
	"github.com/nawaman/codingbooth/src/pkg/docker"
)

// restartBooth restarts a running booth container.
// Usage: coding-booth restart [--name <name>] [--time <seconds>]
func restartBooth(version string) {
	var (
		containerName string
		timeout       int
		verbose       bool
	)

	args := os.Args[2:] // Skip "coding-booth restart"
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
		case "-t", "--time":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --time requires a value")
				os.Exit(1)
			}
			i++
			var err error
			timeout, err = strconv.Atoi(args[i])
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error: Invalid timeout value: %s\n", args[i])
				os.Exit(1)
			}
		case "--verbose":
			verbose = true
		case "-h", "--help":
			showRestartHelp()
			return
		default:
			if strings.HasPrefix(args[i], "-") {
				fmt.Fprintf(os.Stderr, "Unknown option: %s\n", args[i])
				fmt.Fprintln(os.Stderr, "Use 'coding-booth restart --help' for usage information")
				os.Exit(1)
			}
			positionalArgs = append(positionalArgs, args[i])
		}
	}

	// If positional arg provided, use it as container name
	if len(positionalArgs) > 0 && containerName == "" {
		containerName = positionalArgs[0]
	}

	flags := docker.DockerFlags{
		Dryrun:  false,
		Verbose: verbose,
		Silent:  false,
	}

	// Determine which container to restart
	if containerName == "" {
		// Try to infer from current directory
		cwd, err := os.Getwd()
		if err != nil {
			fmt.Fprintln(os.Stderr, "Error: Cannot determine current directory")
			os.Exit(1)
		}
		containerName = sanitizeName(filepath.Base(cwd))
	}

	// Verify container exists and is managed by booth
	inspect, err := docker.InspectContainer(containerName, flags)
	if err != nil {
		if strings.Contains(err.Error(), "No such") {
			fmt.Fprintf(os.Stderr, "Error: No booth '%s' found.\n", containerName)
			fmt.Fprintln(os.Stderr, "Use 'coding-booth list' to see available containers.")
			os.Exit(1)
		}
		fmt.Fprintf(os.Stderr, "Error inspecting container: %v\n", err)
		os.Exit(1)
	}

	if inspect.Labels[booth.LabelManaged] != "true" {
		fmt.Fprintf(os.Stderr, "Error: Container '%s' is not managed by CodingBooth.\n", containerName)
		fmt.Fprintln(os.Stderr, "Use 'coding-booth list' to see booth-managed containers.")
		os.Exit(1)
	}

	// Restart the container
	fmt.Printf("Restarting booth '%s'...\n", containerName)

	err = docker.RestartContainer(containerName, timeout, flags)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error restarting container: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Booth '%s' restarted.\n", containerName)
}

func showRestartHelp() {
	fmt.Println(`Usage: coding-booth restart [OPTIONS] [CONTAINER]

Restart a booth container.

OPTIONS:
  --name <name>      Container name to restart
  -t, --time <sec>   Seconds to wait before force kill (default: 10)
  --verbose          Show verbose output
  -h, --help         Show this help

If no name is provided, the container name is inferred from
the current directory name.

EXAMPLES:
  coding-booth restart                 # Restart booth for current directory
  coding-booth restart my-project      # Restart booth by name
  coding-booth restart -t 30           # Wait 30 seconds before force kill`)
}
