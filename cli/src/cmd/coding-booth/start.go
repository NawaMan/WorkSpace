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

// startBooth starts an existing stopped booth container.
// Usage: coding-booth start [--name <name>] [--code <path>] [--daemon]
func startBooth(version string) {
	var (
		containerName string
		codePath      string
		daemon        bool
		verbose       bool
	)

	args := os.Args[2:] // Skip "coding-booth start"
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
		case "--code":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --code requires a value")
				os.Exit(1)
			}
			i++
			codePath = args[i]
		case "-d", "--daemon":
			daemon = true
		case "--verbose":
			verbose = true
		case "-h", "--help":
			showStartHelp()
			return
		default:
			if strings.HasPrefix(args[i], "-") {
				fmt.Fprintf(os.Stderr, "Unknown option: %s\n", args[i])
				fmt.Fprintln(os.Stderr, "Use 'coding-booth start --help' for usage information")
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

	// Determine which container to start
	if containerName == "" && codePath == "" {
		// Try to infer from current directory
		cwd, err := os.Getwd()
		if err != nil {
			fmt.Fprintln(os.Stderr, "Error: Cannot determine current directory")
			os.Exit(1)
		}
		containerName = sanitizeName(filepath.Base(cwd))
	}

	// Find the container
	var container *docker.ContainerInfo
	var err error

	if codePath != "" {
		// Find by code path
		absPath, err := filepath.Abs(codePath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: Invalid code path: %v\n", err)
			os.Exit(1)
		}
		container, err = docker.FindContainerByCodePath(absPath, flags)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error finding container: %v\n", err)
			os.Exit(1)
		}
		if container == nil {
			fmt.Fprintf(os.Stderr, "Error: No booth found for code path: %s\n", absPath)
			fmt.Fprintln(os.Stderr, "Use 'coding-booth list' to see available containers.")
			os.Exit(1)
		}
		containerName = container.Name
	} else {
		// Verify container exists
		exists, err := docker.ContainerExists(containerName, flags)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error checking container: %v\n", err)
			os.Exit(1)
		}
		if !exists {
			fmt.Fprintf(os.Stderr, "Error: No booth '%s' found.\n", containerName)
			fmt.Fprintln(os.Stderr, "Use 'coding-booth list --stopped' to see available containers.")
			os.Exit(1)
		}
	}

	// Check if container is managed by booth
	inspect, err := docker.InspectContainer(containerName, flags)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error inspecting container: %v\n", err)
		os.Exit(1)
	}

	if inspect.Labels[booth.LabelManaged] != "true" {
		fmt.Fprintf(os.Stderr, "Error: Container '%s' is not managed by CodingBooth.\n", containerName)
		fmt.Fprintln(os.Stderr, "Use 'coding-booth list' to see booth-managed containers.")
		os.Exit(1)
	}

	// Check if container is already running
	if inspect.State.Running {
		fmt.Fprintf(os.Stderr, "Error: Container '%s' is already running.\n", containerName)
		os.Exit(1)
	}

	// Start the container
	attach := !daemon
	fmt.Printf("Starting booth '%s'...\n", containerName)

	err = docker.StartContainer(containerName, attach, flags)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error starting container: %v\n", err)
		os.Exit(1)
	}

	if daemon {
		fmt.Printf("Booth '%s' started in background.\n", containerName)
		// Get port info
		port := inspect.Labels["cb.port"]
		if port == "" {
			// Try to get from environment
			for _, env := range inspect.Config.Env {
				if strings.HasPrefix(env, "CB_HOST_PORT=") {
					port = strings.TrimPrefix(env, "CB_HOST_PORT=")
					break
				}
			}
		}
		if port != "" {
			fmt.Printf("Visit: http://localhost:%s\n", port)
		}
	}
}

// sanitizeName creates a valid container name from a directory name.
func sanitizeName(name string) string {
	// Replace invalid characters with underscores
	var result strings.Builder
	for _, r := range name {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '-' || r == '.' {
			result.WriteRune(r)
		} else {
			result.WriteRune('_')
		}
	}
	return result.String()
}

func showStartHelp() {
	fmt.Println(`Usage: coding-booth start [OPTIONS] [CONTAINER]

Start a stopped booth container.

OPTIONS:
  --name <name>    Container name to start
  --code <path>    Find container by original code path
  -d, --daemon     Start in background (don't attach)
  --verbose        Show verbose output
  -h, --help       Show this help

If no name or path is provided, the container name is inferred from
the current directory name.

EXAMPLES:
  coding-booth start                    # Start booth for current directory
  coding-booth start my-project         # Start booth by name
  coding-booth start --name my-project  # Same as above
  coding-booth start --code /path/to/project
  coding-booth start -d                 # Start in background`)
}
