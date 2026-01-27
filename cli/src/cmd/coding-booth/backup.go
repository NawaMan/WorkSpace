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

// backupImage saves an image to a tar file.
// Usage: coding-booth backup <image> --output <file> [--compress]
func backupImage(version string) {
	var (
		output   string
		compress bool
		verbose  bool
	)

	args := os.Args[2:] // Skip "coding-booth backup"
	var positionalArgs []string

	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "-o", "--output":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "Error: --output requires a value")
				os.Exit(1)
			}
			i++
			output = args[i]
		case "-z", "--compress":
			compress = true
		case "--verbose":
			verbose = true
		case "-h", "--help":
			showBackupHelp()
			return
		default:
			if strings.HasPrefix(args[i], "-") {
				fmt.Fprintf(os.Stderr, "Unknown option: %s\n", args[i])
				fmt.Fprintln(os.Stderr, "Use 'coding-booth backup --help' for usage information")
				os.Exit(1)
			}
			positionalArgs = append(positionalArgs, args[i])
		}
	}

	// Image name is required
	if len(positionalArgs) == 0 {
		fmt.Fprintln(os.Stderr, "Error: Image name is required")
		fmt.Fprintln(os.Stderr, "Example: coding-booth backup myimage:v1 -o myimage.tar")
		os.Exit(1)
	}

	imageName := positionalArgs[0]

	// Output file is required
	if output == "" {
		fmt.Fprintln(os.Stderr, "Error: --output is required")
		fmt.Fprintln(os.Stderr, "Example: coding-booth backup myimage:v1 -o myimage.tar")
		os.Exit(1)
	}

	flags := docker.DockerFlags{
		Dryrun:  false,
		Verbose: verbose,
		Silent:  false,
	}

	// Add .gz extension if compressing and not already present
	if compress && !strings.HasSuffix(strings.ToLower(output), ".gz") && !strings.HasSuffix(strings.ToLower(output), ".tgz") {
		output = output + ".gz"
	}

	// Backup the image
	fmt.Printf("Saving image '%s' to '%s'", imageName, output)
	if compress {
		fmt.Print(" (compressed)")
	}
	fmt.Println("...")

	var err error
	if compress {
		err = docker.SaveImageCompressed(imageName, output, flags)
	} else {
		err = docker.SaveImage(imageName, output, flags)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "Error saving image: %v\n", err)
		os.Exit(1)
	}

	// Get file size
	fileInfo, _ := os.Stat(output)
	var sizeStr string
	if fileInfo != nil {
		size := fileInfo.Size()
		if size > 1024*1024*1024 {
			sizeStr = fmt.Sprintf("%.2f GB", float64(size)/(1024*1024*1024))
		} else if size > 1024*1024 {
			sizeStr = fmt.Sprintf("%.2f MB", float64(size)/(1024*1024))
		} else if size > 1024 {
			sizeStr = fmt.Sprintf("%.2f KB", float64(size)/1024)
		} else {
			sizeStr = fmt.Sprintf("%d bytes", size)
		}
	}

	fmt.Printf("Successfully saved to '%s'", output)
	if sizeStr != "" {
		fmt.Printf(" (%s)", sizeStr)
	}
	fmt.Println()
	fmt.Println()
	fmt.Println("To restore this image:")
	fmt.Printf("  coding-booth restore %s\n", output)
}

func showBackupHelp() {
	fmt.Println(`Usage: coding-booth backup [OPTIONS] <IMAGE>

Save a Docker image to a tar file for offline sharing or backup.

OPTIONS:
  -o, --output <file>  Output file path (required)
  -z, --compress       Compress with gzip (.tar.gz)
  --verbose            Show verbose output
  -h, --help           Show this help

EXAMPLES:
  coding-booth backup mywork:v1 -o mywork.tar
  coding-booth backup mywork:v1 -o mywork.tar.gz --compress
  coding-booth backup mywork:v1 -o ~/backups/mywork.tar`)
}
