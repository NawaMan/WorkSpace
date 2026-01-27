// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// CommitContainer creates a new image from a container's changes.
// container is the container name or ID.
// tag is the image tag (e.g., "myimage:v1").
// message is an optional commit message.
func CommitContainer(container string, tag string, message string, flags DockerFlags) error {
	args := ilist.NewAppendableList[ilist.List[string]]()

	if message != "" {
		args.Append(ilist.NewList("-m", message))
	}

	args.Append(ilist.NewList(container, tag))

	return Docker(flags, "commit", args.Snapshot())
}

// PushImage pushes an image to a registry.
// image is the full image name including registry and tag (e.g., "registry.example.com/myimage:v1").
func PushImage(image string, flags DockerFlags) error {
	args := ilist.NewList(ilist.NewList(image))
	return Docker(flags, "push", args)
}

// TagImage tags an image with a new name.
// source is the existing image name/tag.
// target is the new name/tag.
func TagImage(source string, target string, flags DockerFlags) error {
	args := ilist.NewList(ilist.NewList(source, target))
	return Docker(flags, "tag", args)
}

// SaveImage saves an image to a tar archive.
// image is the image name/tag.
// output is the output file path.
// Returns the full path of the saved file.
func SaveImage(image string, output string, flags DockerFlags) error {
	args := ilist.NewList(ilist.NewList("-o", output, image))
	return Docker(flags, "save", args)
}

// SaveImageCompressed saves an image to a gzip-compressed tar archive.
// This uses a pipe to docker save | gzip instead of docker save -o to enable compression.
// image is the image name/tag.
// output is the output file path (should end with .tar.gz or .tgz).
func SaveImageCompressed(image string, output string, flags DockerFlags) error {
	if flags.Dryrun || flags.Verbose {
		printCmd("docker", []string{"save"}, []string{image}, []string{"|", "gzip", ">", output})
	}

	if flags.Dryrun {
		return nil
	}

	// Create the output file
	outFile, err := os.Create(output)
	if err != nil {
		return fmt.Errorf("failed to create output file: %w", err)
	}
	defer outFile.Close()

	// Create the gzip command
	gzipCmd := exec.Command("gzip")
	gzipCmd.Stdout = outFile
	gzipCmd.Stderr = os.Stderr

	// Get gzip's stdin pipe
	gzipIn, err := gzipCmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("failed to create gzip stdin pipe: %w", err)
	}

	// Create the docker save command
	dockerCmd := exec.Command("docker", "save", image)
	dockerCmd.Stdout = gzipIn
	dockerCmd.Stderr = os.Stderr

	// Start gzip first
	if err := gzipCmd.Start(); err != nil {
		return fmt.Errorf("failed to start gzip: %w", err)
	}

	// Start docker save
	if err := dockerCmd.Start(); err != nil {
		gzipCmd.Process.Kill()
		return fmt.Errorf("failed to start docker save: %w", err)
	}

	// Wait for docker save to complete
	dockerErr := dockerCmd.Wait()
	gzipIn.Close()

	// Wait for gzip to complete
	gzipErr := gzipCmd.Wait()

	if dockerErr != nil {
		return fmt.Errorf("docker save failed: %w", dockerErr)
	}
	if gzipErr != nil {
		return fmt.Errorf("gzip failed: %w", gzipErr)
	}

	return nil
}

// LoadImage loads an image from a tar archive.
// input is the input file path.
// Returns the loaded image name/tag.
func LoadImage(input string, flags DockerFlags) (string, error) {
	args := ilist.NewList(ilist.NewList("-i", input))

	output, err := DockerOutput(flags, "load", args)
	if err != nil {
		return "", err
	}

	// Parse the output to get the image name
	// Docker load outputs: "Loaded image: image:tag" or "Loaded image ID: sha256:..."
	output = strings.TrimSpace(output)
	lines := strings.Split(output, "\n")

	for _, line := range lines {
		if strings.HasPrefix(line, "Loaded image:") {
			return strings.TrimSpace(strings.TrimPrefix(line, "Loaded image:")), nil
		}
		if strings.HasPrefix(line, "Loaded image ID:") {
			return strings.TrimSpace(strings.TrimPrefix(line, "Loaded image ID:")), nil
		}
	}

	// If we can't find the image name in output, return empty with no error
	return "", nil
}

// LoadImageCompressed loads a gzip-compressed image from a tar.gz archive.
// input is the input file path (should be .tar.gz or .tgz).
// Returns the loaded image name/tag.
func LoadImageCompressed(input string, flags DockerFlags) (string, error) {
	if flags.Dryrun || flags.Verbose {
		printCmd("gunzip", []string{"-c"}, []string{input}, []string{"|", "docker", "load"})
	}

	if flags.Dryrun {
		return "", nil
	}

	// Open the compressed file
	inFile, err := os.Open(input)
	if err != nil {
		return "", fmt.Errorf("failed to open input file: %w", err)
	}
	defer inFile.Close()

	// Create gunzip command
	gunzipCmd := exec.Command("gunzip", "-c")
	gunzipCmd.Stdin = inFile
	gunzipCmd.Stderr = os.Stderr

	// Get gunzip's stdout pipe
	gunzipOut, err := gunzipCmd.StdoutPipe()
	if err != nil {
		return "", fmt.Errorf("failed to create gunzip stdout pipe: %w", err)
	}

	// Create docker load command
	dockerCmd := exec.Command("docker", "load")
	dockerCmd.Stdin = gunzipOut
	dockerCmd.Stderr = os.Stderr

	// Capture docker load output
	var dockerOut strings.Builder
	dockerCmd.Stdout = &dockerOut

	// Start gunzip first
	if err := gunzipCmd.Start(); err != nil {
		return "", fmt.Errorf("failed to start gunzip: %w", err)
	}

	// Start docker load
	if err := dockerCmd.Start(); err != nil {
		gunzipCmd.Process.Kill()
		return "", fmt.Errorf("failed to start docker load: %w", err)
	}

	// Wait for both to complete
	gunzipErr := gunzipCmd.Wait()
	dockerErr := dockerCmd.Wait()

	if gunzipErr != nil {
		return "", fmt.Errorf("gunzip failed: %w", gunzipErr)
	}
	if dockerErr != nil {
		return "", fmt.Errorf("docker load failed: %w", dockerErr)
	}

	// Parse the output to get the image name
	output := strings.TrimSpace(dockerOut.String())
	lines := strings.Split(output, "\n")

	for _, line := range lines {
		if strings.HasPrefix(line, "Loaded image:") {
			return strings.TrimSpace(strings.TrimPrefix(line, "Loaded image:")), nil
		}
		if strings.HasPrefix(line, "Loaded image ID:") {
			return strings.TrimSpace(strings.TrimPrefix(line, "Loaded image ID:")), nil
		}
	}

	return "", nil
}

// IsCompressedArchive checks if a file appears to be gzip-compressed.
// Returns true if the file has a .gz, .tgz extension or gzip magic bytes.
func IsCompressedArchive(path string) bool {
	lower := strings.ToLower(path)
	if strings.HasSuffix(lower, ".gz") || strings.HasSuffix(lower, ".tgz") {
		return true
	}

	// Check magic bytes (gzip files start with 0x1f 0x8b)
	file, err := os.Open(path)
	if err != nil {
		return false
	}
	defer file.Close()

	magic := make([]byte, 2)
	if _, err := file.Read(magic); err != nil {
		return false
	}

	return magic[0] == 0x1f && magic[1] == 0x8b
}

// ImageExists checks if an image exists locally.
func ImageExists(image string, flags DockerFlags) (bool, error) {
	args := ilist.NewList(ilist.NewList(image))

	_, err := DockerOutput(flags, "image", ilist.NewList(ilist.NewList("inspect"), ilist.NewList(image)))
	if err != nil {
		if exitErr, ok := err.(*DockerExitError); ok && exitErr.ExitCode == 1 {
			return false, nil
		}
		return false, err
	}
	_ = args // suppress unused warning
	return true, nil
}
