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

// restoreImage loads an image from a tar file.
// Usage: coding-booth restore <file>
func restoreImage(version string) {
	var verbose bool

	args := os.Args[2:] // Skip "coding-booth restore"
	var positionalArgs []string

	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--verbose":
			verbose = true
		case "-h", "--help":
			showRestoreHelp()
			return
		default:
			if strings.HasPrefix(args[i], "-") {
				fmt.Fprintf(os.Stderr, "Unknown option: %s\n", args[i])
				fmt.Fprintln(os.Stderr, "Use 'coding-booth restore --help' for usage information")
				os.Exit(1)
			}
			positionalArgs = append(positionalArgs, args[i])
		}
	}

	// File path is required
	if len(positionalArgs) == 0 {
		fmt.Fprintln(os.Stderr, "Error: File path is required")
		fmt.Fprintln(os.Stderr, "Example: coding-booth restore myimage.tar")
		os.Exit(1)
	}

	filePath := positionalArgs[0]

	// Check if file exists
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		fmt.Fprintf(os.Stderr, "Error: File not found: %s\n", filePath)
		os.Exit(1)
	}

	flags := docker.DockerFlags{
		Dryrun:  false,
		Verbose: verbose,
		Silent:  false,
	}

	// Detect if file is compressed
	isCompressed := docker.IsCompressedArchive(filePath)

	fmt.Printf("Loading image from '%s'", filePath)
	if isCompressed {
		fmt.Print(" (compressed)")
	}
	fmt.Println("...")

	var imageName string
	var err error

	if isCompressed {
		imageName, err = docker.LoadImageCompressed(filePath, flags)
	} else {
		imageName, err = docker.LoadImage(filePath, flags)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading image: %v\n", err)
		os.Exit(1)
	}

	if imageName != "" {
		fmt.Printf("Successfully loaded image: %s\n", imageName)
		fmt.Println()
		fmt.Println("To use this image:")
		fmt.Printf("  coding-booth run --image %s\n", imageName)
	} else {
		fmt.Println("Image loaded successfully.")
		fmt.Println("Run 'docker images' to see the loaded image.")
	}
}

func showRestoreHelp() {
	fmt.Println(`Usage: coding-booth restore [OPTIONS] <FILE>

Load a Docker image from a tar file.

OPTIONS:
  --verbose   Show verbose output
  -h, --help  Show this help

The command automatically detects if the file is gzip-compressed
(.tar.gz, .tgz, or by checking magic bytes).

EXAMPLES:
  coding-booth restore mywork.tar
  coding-booth restore mywork.tar.gz
  coding-booth restore ~/backups/mywork.tar`)
}
