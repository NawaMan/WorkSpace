// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// ContainerInfo represents basic container information from docker ps.
type ContainerInfo struct {
	ID      string            // Container ID
	Name    string            // Container name
	Image   string            // Image name
	Status  string            // Status string (e.g., "Up 2 hours", "Exited (0) 5 minutes ago")
	State   string            // State (running, exited, etc.)
	Ports   string            // Port mappings
	Labels  map[string]string // Container labels
	Created string            // Created timestamp
}

// ContainerInspect represents detailed container information from docker inspect.
type ContainerInspect struct {
	ID     string            // Container ID
	Name   string            // Container name
	State  ContainerState    // Container state
	Config ContainerConfig   // Container configuration
	Labels map[string]string // Container labels
}

// ContainerState represents the state of a container.
type ContainerState struct {
	Running    bool   // Is the container running
	Paused     bool   // Is the container paused
	Restarting bool   // Is the container restarting
	OOMKilled  bool   // Was the container killed due to OOM
	Dead       bool   // Is the container dead
	Pid        int    // Process ID
	ExitCode   int    // Exit code
	Error      string // Error message
	StartedAt  string // Started at timestamp
	FinishedAt string // Finished at timestamp
}

// ContainerConfig represents the configuration of a container.
type ContainerConfig struct {
	Image  string   // Image name
	Cmd    []string // Command
	Env    []string // Environment variables
	Labels map[string]string
}

// ListContainers returns a list of containers matching the given filter.
// filter should be a docker filter string like "label=cb.managed=true"
// If filter is empty, all containers are returned.
func ListContainers(filter string, all bool, flags DockerFlags) ([]ContainerInfo, error) {
	args := ilist.NewAppendableList[ilist.List[string]]()

	// Build format string to get JSON output with all needed fields
	format := `{"ID":"{{.ID}}","Name":"{{.Names}}","Image":"{{.Image}}","Status":"{{.Status}}","State":"{{.State}}","Ports":"{{.Ports}}","Labels":"{{.Labels}}","Created":"{{.CreatedAt}}"}`
	args.Append(ilist.NewList("--format", format))

	if all {
		args.Append(ilist.NewList("-a"))
	}

	if filter != "" {
		args.Append(ilist.NewList("--filter", filter))
	}

	output, err := DockerOutput(flags, "ps", args.Snapshot())
	if err != nil {
		return nil, err
	}

	// Parse each line as JSON
	var containers []ContainerInfo
	lines := strings.Split(strings.TrimSpace(output), "\n")
	for _, line := range lines {
		if line == "" {
			continue
		}

		var raw struct {
			ID      string `json:"ID"`
			Name    string `json:"Name"`
			Image   string `json:"Image"`
			Status  string `json:"Status"`
			State   string `json:"State"`
			Ports   string `json:"Ports"`
			Labels  string `json:"Labels"`
			Created string `json:"Created"`
		}

		if err := json.Unmarshal([]byte(line), &raw); err != nil {
			// If JSON parsing fails, skip this line
			continue
		}

		// Parse labels from the map=value format
		labels := parseLabels(raw.Labels)

		containers = append(containers, ContainerInfo{
			ID:      raw.ID,
			Name:    raw.Name,
			Image:   raw.Image,
			Status:  raw.Status,
			State:   raw.State,
			Ports:   raw.Ports,
			Labels:  labels,
			Created: raw.Created,
		})
	}

	return containers, nil
}

// parseLabels parses the docker labels string format into a map.
// Docker outputs labels as "key1=value1,key2=value2,..."
func parseLabels(labelsStr string) map[string]string {
	labels := make(map[string]string)
	if labelsStr == "" {
		return labels
	}

	// Split by comma, but handle values that might contain commas
	pairs := strings.Split(labelsStr, ",")
	for _, pair := range pairs {
		parts := strings.SplitN(pair, "=", 2)
		if len(parts) == 2 {
			labels[parts[0]] = parts[1]
		}
	}

	return labels
}

// InspectContainer returns detailed information about a container.
func InspectContainer(name string, flags DockerFlags) (*ContainerInspect, error) {
	args := ilist.NewList(ilist.NewList(name))

	output, err := DockerOutput(flags, "inspect", args)
	if err != nil {
		return nil, err
	}

	// Docker inspect returns a JSON array
	var inspects []struct {
		ID     string `json:"Id"`
		Name   string `json:"Name"`
		State  struct {
			Running    bool   `json:"Running"`
			Paused     bool   `json:"Paused"`
			Restarting bool   `json:"Restarting"`
			OOMKilled  bool   `json:"OOMKilled"`
			Dead       bool   `json:"Dead"`
			Pid        int    `json:"Pid"`
			ExitCode   int    `json:"ExitCode"`
			Error      string `json:"Error"`
			StartedAt  string `json:"StartedAt"`
			FinishedAt string `json:"FinishedAt"`
		} `json:"State"`
		Config struct {
			Image  string            `json:"Image"`
			Cmd    []string          `json:"Cmd"`
			Env    []string          `json:"Env"`
			Labels map[string]string `json:"Labels"`
		} `json:"Config"`
	}

	if err := json.Unmarshal([]byte(output), &inspects); err != nil {
		return nil, fmt.Errorf("failed to parse docker inspect output: %w", err)
	}

	if len(inspects) == 0 {
		return nil, fmt.Errorf("container %s not found", name)
	}

	inspect := inspects[0]
	return &ContainerInspect{
		ID:   inspect.ID,
		Name: strings.TrimPrefix(inspect.Name, "/"), // Docker adds leading /
		State: ContainerState{
			Running:    inspect.State.Running,
			Paused:     inspect.State.Paused,
			Restarting: inspect.State.Restarting,
			OOMKilled:  inspect.State.OOMKilled,
			Dead:       inspect.State.Dead,
			Pid:        inspect.State.Pid,
			ExitCode:   inspect.State.ExitCode,
			Error:      inspect.State.Error,
			StartedAt:  inspect.State.StartedAt,
			FinishedAt: inspect.State.FinishedAt,
		},
		Config: ContainerConfig{
			Image:  inspect.Config.Image,
			Cmd:    inspect.Config.Cmd,
			Env:    inspect.Config.Env,
			Labels: inspect.Config.Labels,
		},
		Labels: inspect.Config.Labels,
	}, nil
}

// StartContainer starts a stopped container.
// If attach is true, attaches stdin/stdout/stderr (-ai flags).
// If attach is false, starts in detached mode.
func StartContainer(name string, attach bool, flags DockerFlags) error {
	args := ilist.NewAppendableList[ilist.List[string]]()

	if attach {
		args.Append(ilist.NewList("-ai"))
	}
	args.Append(ilist.NewList(name))

	return Docker(flags, "start", args.Snapshot())
}

// StopContainer stops a running container.
// If force is true, sends SIGKILL instead of SIGTERM.
// timeout specifies seconds to wait before force killing (default 10 if 0).
func StopContainer(name string, force bool, timeout int, flags DockerFlags) error {
	args := ilist.NewAppendableList[ilist.List[string]]()

	if timeout > 0 {
		args.Append(ilist.NewList("-t", fmt.Sprintf("%d", timeout)))
	}

	args.Append(ilist.NewList(name))

	if force {
		return Docker(flags, "kill", args.Snapshot())
	}
	return Docker(flags, "stop", args.Snapshot())
}

// RemoveContainer removes a container.
// If force is true, removes even if the container is running.
func RemoveContainer(name string, force bool, flags DockerFlags) error {
	args := ilist.NewAppendableList[ilist.List[string]]()

	if force {
		args.Append(ilist.NewList("-f"))
	}
	args.Append(ilist.NewList(name))

	return Docker(flags, "rm", args.Snapshot())
}

// RestartContainer restarts a container.
// timeout specifies seconds to wait before force killing during stop (default 10 if 0).
func RestartContainer(name string, timeout int, flags DockerFlags) error {
	args := ilist.NewAppendableList[ilist.List[string]]()

	if timeout > 0 {
		args.Append(ilist.NewList("-t", fmt.Sprintf("%d", timeout)))
	}

	args.Append(ilist.NewList(name))

	return Docker(flags, "restart", args.Snapshot())
}

// FindContainerByCodePath finds a container by its cb.code-path label.
// Returns nil if no container is found.
func FindContainerByCodePath(codePath string, flags DockerFlags) (*ContainerInfo, error) {
	filter := fmt.Sprintf("label=cb.code-path=%s", codePath)
	containers, err := ListContainers(filter, true, flags)
	if err != nil {
		return nil, err
	}

	if len(containers) == 0 {
		return nil, nil
	}

	// Return the first matching container
	return &containers[0], nil
}

// IsContainerRunning checks if a container with the given name is running.
func IsContainerRunning(name string, flags DockerFlags) (bool, error) {
	inspect, err := InspectContainer(name, flags)
	if err != nil {
		// Container doesn't exist or other error
		return false, err
	}

	return inspect.State.Running, nil
}

// ContainerExists checks if a container with the given name exists.
func ContainerExists(name string, flags DockerFlags) (bool, error) {
	_, err := InspectContainer(name, flags)
	if err != nil {
		// Check if it's a "not found" error vs other errors
		if strings.Contains(err.Error(), "No such") {
			return false, nil
		}
		return false, err
	}
	return true, nil
}
