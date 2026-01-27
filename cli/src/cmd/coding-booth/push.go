// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/docker"
)

// pushImage pushes a committed image to a registry.
// Usage: coding-booth push <image> [--registry <url>]
func pushImage(version string) {
	var (
		registry string
		verbose  bool
	)

	args := os.Args[2:] // Skip "coding-booth push"
	var positionalArgs []string

	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--registry":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --registry requires a value")
				os.Exit(1)
			}
			i++
			registry = args[i]
		case "--verbose":
			verbose = true
		case "-h", "--help":
			showPushHelp()
			return
		default:
			if strings.HasPrefix(args[i], "-") {
				fmt.Fprintf(os.Stderr, "Unknown option: %s\n", args[i])
				fmt.Fprintln(os.Stderr, "Use 'coding-booth push --help' for usage information")
				os.Exit(1)
			}
			positionalArgs = append(positionalArgs, args[i])
		}
	}

	// Image name is required
	if len(positionalArgs) == 0 {
		fmt.Fprintln(os.Stderr, "Error: Image name is required")
		fmt.Fprintln(os.Stderr, "Example: coding-booth push myimage:v1")
		os.Exit(1)
	}

	imageName := positionalArgs[0]

	flags := docker.DockerFlags{
		Dryrun:  false,
		Verbose: verbose,
		Silent:  false,
	}

	// If registry is specified, tag the image with the registry prefix
	targetImage := imageName
	if registry != "" {
		// If the image doesn't already include the registry, prepend it
		if !strings.Contains(imageName, "/") || !strings.Contains(strings.Split(imageName, "/")[0], ".") {
			targetImage = registry + "/" + imageName
		}

		fmt.Printf("Tagging '%s' as '%s'...\n", imageName, targetImage)
		err := docker.TagImage(imageName, targetImage, flags)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error tagging image: %v\n", err)
			os.Exit(1)
		}
	}

	// Push the image
	fmt.Printf("Pushing '%s'...\n", targetImage)

	err := docker.PushImage(targetImage, flags)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error pushing image: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Successfully pushed '%s'\n", targetImage)
	fmt.Println()
	fmt.Println("To use this image:")
	fmt.Printf("  coding-booth run --image %s\n", targetImage)
}

func showPushHelp() {
	fmt.Println(`Usage: coding-booth push [OPTIONS] <IMAGE>

Push a Docker image to a container registry.

OPTIONS:
  --registry <url>  Registry URL (e.g., ghcr.io/username)
  --verbose         Show verbose output
  -h, --help        Show this help

If --registry is specified and the image doesn't include a registry,
the image will be tagged with the registry prefix before pushing.

EXAMPLES:
  coding-booth push mywork:v1
  coding-booth push mywork:v1 --registry ghcr.io/myuser
  coding-booth push ghcr.io/myuser/mywork:v1`)
}
