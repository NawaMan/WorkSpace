// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
	"strings"
	"text/tabwriter"

	"github.com/nawaman/codingbooth/src/pkg/booth"
	"github.com/nawaman/codingbooth/src/pkg/docker"
)

// listBooths shows all booth-managed containers.
// Usage: coding-booth list [--running] [--stopped] [--quiet]
func listBooths(version string) {
	// Parse flags
	var (
		showRunning bool
		showStopped bool
		quiet       bool
		verbose     bool
	)

	args := os.Args[2:] // Skip "coding-booth list"
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--running":
			showRunning = true
		case "--stopped":
			showStopped = true
		case "-q", "--quiet":
			quiet = true
		case "--verbose":
			verbose = true
		case "-h", "--help":
			showListHelp()
			return
		default:
			fmt.Fprintf(os.Stderr, "Unknown option: %s\n", args[i])
			fmt.Fprintln(os.Stderr, "Use 'coding-booth list --help' for usage information")
			os.Exit(1)
		}
	}

	// If neither --running nor --stopped specified, show all
	showAll := !showRunning && !showStopped

	flags := docker.DockerFlags{
		Dryrun:  false,
		Verbose: verbose,
		Silent:  false,
	}

	// List all booth-managed containers
	filter := booth.LabelFilter()
	containers, err := docker.ListContainers(filter, true, flags)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error listing containers: %v\n", err)
		os.Exit(1)
	}

	// Filter by state if requested
	var filtered []docker.ContainerInfo
	for _, c := range containers {
		isRunning := strings.ToLower(c.State) == "running"

		if showAll || (showRunning && isRunning) || (showStopped && !isRunning) {
			filtered = append(filtered, c)
		}
	}

	if len(filtered) == 0 {
		if !quiet {
			fmt.Println("No booth containers found.")
		}
		return
	}

	// Output
	if quiet {
		// Quiet mode: only print container names
		for _, c := range filtered {
			fmt.Println(c.Name)
		}
		return
	}

	// Table output
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "NAME\tSTATUS\tVARIANT\tPORT\tCODE PATH\tCREATED")

	for _, c := range filtered {
		variant := c.Labels[booth.LabelVariant]
		codePath := c.Labels[booth.LabelCodePath]
		created := c.Labels[booth.LabelCreatedAt]

		// Extract port from Ports string (e.g., "0.0.0.0:10000->10000/tcp")
		port := extractPort(c.Ports)

		// Truncate code path if too long
		if len(codePath) > 40 {
			codePath = "..." + codePath[len(codePath)-37:]
		}

		// Format created time
		if len(created) > 19 {
			created = created[:19] // Truncate to "2024-01-01T12:00:00"
		}

		fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\n",
			c.Name,
			formatStatus(c.Status),
			variant,
			port,
			codePath,
			created,
		)
	}
	w.Flush()
}

// extractPort extracts the host port from a Docker ports string.
// Example: "0.0.0.0:10000->10000/tcp" -> "10000"
func extractPort(ports string) string {
	if ports == "" {
		return "-"
	}

	// Find the host port (before "->")
	parts := strings.Split(ports, "->")
	if len(parts) < 1 {
		return "-"
	}

	hostPart := parts[0]
	// Handle "0.0.0.0:10000" format
	colonIdx := strings.LastIndex(hostPart, ":")
	if colonIdx >= 0 && colonIdx < len(hostPart)-1 {
		return hostPart[colonIdx+1:]
	}

	return "-"
}

// formatStatus returns a short status string.
func formatStatus(status string) string {
	status = strings.ToLower(status)
	if strings.HasPrefix(status, "up") {
		return "Running"
	}
	if strings.HasPrefix(status, "exited") {
		return "Stopped"
	}
	if strings.HasPrefix(status, "created") {
		return "Created"
	}
	if strings.HasPrefix(status, "paused") {
		return "Paused"
	}
	return status
}

func showListHelp() {
	fmt.Println(`Usage: coding-booth list [OPTIONS]

List all booth-managed containers.

OPTIONS:
  --running    Show only running containers
  --stopped    Show only stopped containers
  -q, --quiet  Show only container names
  --verbose    Show verbose output
  -h, --help   Show this help

EXAMPLES:
  coding-booth list              # List all booth containers
  coding-booth list --running    # List only running booths
  coding-booth list --stopped    # List only stopped booths
  coding-booth list -q           # List container names only`)
}
