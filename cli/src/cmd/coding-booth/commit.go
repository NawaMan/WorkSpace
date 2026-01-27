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

// commitBooth creates a Docker image from a container's current state.
// Usage: coding-booth commit --tag <tag> [--name <name>] [--message <msg>]
func commitBooth(version string) {
	var (
		containerName string
		tag           string
		message       string
		verbose       bool
	)

	args := os.Args[2:] // Skip "coding-booth commit"
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
		case "-t", "--tag":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --tag requires a value")
				os.Exit(1)
			}
			i++
			tag = args[i]
		case "-m", "--message":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --message requires a value")
				os.Exit(1)
			}
			i++
			message = args[i]
		case "--verbose":
			verbose = true
		case "-h", "--help":
			showCommitHelp()
			return
		default:
			if strings.HasPrefix(args[i], "-") {
				fmt.Fprintf(os.Stderr, "Unknown option: %s\n", args[i])
				fmt.Fprintln(os.Stderr, "Use 'coding-booth commit --help' for usage information")
				os.Exit(1)
			}
			positionalArgs = append(positionalArgs, args[i])
		}
	}

	// Tag is required
	if tag == "" {
		fmt.Fprintln(os.Stderr, "Error: --tag is required")
		fmt.Fprintln(os.Stderr, "Example: coding-booth commit --tag myimage:v1")
		os.Exit(1)
	}

	flags := docker.DockerFlags{
		Dryrun:  false,
		Verbose: verbose,
		Silent:  false,
	}

	// Determine which container to commit
	if containerName == "" && len(positionalArgs) > 0 {
		containerName = positionalArgs[0]
	}

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

	// Commit the container
	fmt.Printf("Committing booth '%s' as '%s'...\n", containerName, tag)

	err = docker.CommitContainer(containerName, tag, message, flags)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error committing container: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Successfully created image '%s'\n", tag)
	fmt.Println()
	fmt.Println("Next steps:")
	fmt.Printf("  • Push to registry:   coding-booth push %s\n", tag)
	fmt.Printf("  • Save to file:       coding-booth backup %s -o <file>.tar\n", tag)
	fmt.Printf("  • Run the image:      coding-booth run --image %s\n", tag)
}

func showCommitHelp() {
	fmt.Println(`Usage: coding-booth commit [OPTIONS] [CONTAINER]

Create a Docker image from a container's current state.

OPTIONS:
  --name <name>       Container name to commit
  -t, --tag <tag>     Image tag to create (required)
  -m, --message <msg> Commit message
  --verbose           Show verbose output
  -h, --help          Show this help

If no container name is provided, it is inferred from the current directory.

EXAMPLES:
  coding-booth commit --tag mywork:v1
  coding-booth commit --tag mywork:v1 --name my-project
  coding-booth commit --tag mywork:v1 -m "Added dependencies"
  coding-booth commit my-project --tag registry.example.com/mywork:v1`)
}
