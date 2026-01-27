// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"time"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// Container label keys for booth-managed containers.
// These labels enable lifecycle management commands (list, start, stop, etc.)
// to identify and filter booth containers.
const (
	// LabelManaged marks a container as managed by CodingBooth
	LabelManaged = "cb.managed"

	// LabelProject stores the project name
	LabelProject = "cb.project"

	// LabelVariant stores the variant used (base, notebook, codeserver, etc.)
	LabelVariant = "cb.variant"

	// LabelCodePath stores the absolute path to the code directory on the host
	LabelCodePath = "cb.code-path"

	// LabelCreatedAt stores the ISO 8601 timestamp when the container was created
	LabelCreatedAt = "cb.created-at"

	// LabelVersion stores the CodingBooth version that created the container
	LabelVersion = "cb.version"

	// LabelKeepAlive indicates if the container should be kept after stopping
	LabelKeepAlive = "cb.keep-alive"
)

// LabelFilter returns the docker filter string to find booth-managed containers
func LabelFilter() string {
	return "label=" + LabelManaged + "=true"
}

// GenerateLabels creates Docker --label arguments from the AppContext.
// Returns a list of label argument pairs (e.g., ["--label", "cb.managed=true", "--label", "cb.project=myapp"])
func GenerateLabels(ctx appctx.AppContext) ilist.List[string] {
	labels := ilist.NewAppendableList[string]()

	// Add each label as a pair of arguments
	labels.Append("--label", LabelManaged+"=true")
	labels.Append("--label", LabelProject+"="+ctx.ProjectName())
	labels.Append("--label", LabelVariant+"="+ctx.Variant())
	labels.Append("--label", LabelCodePath+"="+ctx.Code())
	labels.Append("--label", LabelCreatedAt+"="+time.Now().UTC().Format(time.RFC3339))
	labels.Append("--label", LabelVersion+"="+ctx.CbVersion())

	// Store keep-alive status for stop command to know whether to auto-remove
	keepAlive := "false"
	if ctx.KeepAlive() {
		keepAlive = "true"
	}
	labels.Append("--label", LabelKeepAlive+"="+keepAlive)

	return labels.Snapshot()
}
