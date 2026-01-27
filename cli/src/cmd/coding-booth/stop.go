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

// stopBooth stops a running booth container.
// Usage: coding-booth stop [--name <name>] [--force] [--time <seconds>]
func stopBooth(version string) {
	var (
		containerName string
		force         bool
		timeout       int
		verbose       bool
	)

	args := os.Args[2:] // Skip "coding-booth stop"
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
			showStopHelp()
			return
		default:
			if strings.HasPrefix(args[i], "-") {
				fmt.Fprintf(os.Stderr, "Unknown option: %s\n", args[i])
				fmt.Fprintln(os.Stderr, "Use 'coding-booth stop --help' for usage information")
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

	// Determine which container to stop
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
			fmt.Fprintln(os.Stderr, "Use 'coding-booth list --running' to see running containers.")
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

	// Check if container is running
	if !inspect.State.Running {
		fmt.Fprintf(os.Stderr, "Error: Container '%s' is not running.\n", containerName)
		os.Exit(1)
	}

	// Stop the container
	fmt.Printf("Stopping booth '%s'...\n", containerName)

	err = docker.StopContainer(containerName, force, timeout, flags)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error stopping container: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Booth '%s' stopped.\n", containerName)

	// Check if we should auto-remove the container
	keepAlive := inspect.Labels[booth.LabelKeepAlive]
	if keepAlive != "true" {
		// Container was not started with --keep-alive, remove it
		fmt.Printf("Removing container '%s' (no --keep-alive)...\n", containerName)
		err = docker.RemoveContainer(containerName, false, flags)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Warning: Failed to remove container: %v\n", err)
		} else {
			fmt.Printf("Container '%s' removed.\n", containerName)
		}
	} else {
		fmt.Printf("Container '%s' kept (--keep-alive was set).\n", containerName)
		fmt.Printf("To restart: coding-booth start %s\n", containerName)
		fmt.Printf("To remove:  coding-booth remove %s\n", containerName)
	}
}

func showStopHelp() {
	fmt.Println(`Usage: coding-booth stop [OPTIONS] [CONTAINER]

Stop a running booth container.

OPTIONS:
  --name <name>      Container name to stop
  -f, --force        Force stop (SIGKILL instead of SIGTERM)
  -t, --time <sec>   Seconds to wait before force kill (default: 10)
  --verbose          Show verbose output
  -h, --help         Show this help

If no name is provided, the container name is inferred from
the current directory name.

If the container was started without --keep-alive, it will be
automatically removed after stopping.

EXAMPLES:
  coding-booth stop                    # Stop booth for current directory
  coding-booth stop my-project         # Stop booth by name
  coding-booth stop --force            # Force stop immediately
  coding-booth stop -t 30              # Wait 30 seconds before force kill`)
}
