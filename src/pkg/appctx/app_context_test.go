package appctx

import (
	"testing"
)

// TestNewAppContext verifies constructor initializes all defaults correctly.
func TestNewAppContext(t *testing.T) {
	ctx := NewAppContext("0.11.0")

	// Verify version & paths defaults
	if ctx.WsVersion() != "0.11.0" {
		t.Errorf("WsVersion() = %q, want %q", ctx.WsVersion(), "0.11.0")
	}
	if ctx.PrebuildRepo() != "nawaman/workspace" {
		t.Errorf("PrebuildRepo() = %q, want %q", ctx.PrebuildRepo(), "nawaman/workspace")
	}
	if ctx.FileNotUsed() != "none" {
		t.Errorf("FileNotUsed() = %q, want %q", ctx.FileNotUsed(), "none")
	}
	if ctx.SetupsDir() != "/opt/workspace/setups" {
		t.Errorf("SetupsDir() = %q, want %q", ctx.SetupsDir(), "/opt/workspace/setups")
	}

	// Verify flag defaults
	if ctx.Dryrun() != false {
		t.Errorf("Dryrun() = %v, want false", ctx.Dryrun())
	}
	if ctx.Verbose() != false {
		t.Errorf("Verbose() = %v, want false", ctx.Verbose())
	}

	// Verify image configuration defaults
	if ctx.Variant() != "default" {
		t.Errorf("Variant() = %q, want %q", ctx.Variant(), "default")
	}
	if ctx.Version() != "latest" {
		t.Errorf("Version() = %q, want %q", ctx.Version(), "latest")
	}

	// Verify container configuration defaults
	if ctx.WorkspacePort() != "NEXT" {
		t.Errorf("WorkspacePort() = %q, want %q", ctx.WorkspacePort(), "NEXT")
	}

	// Verify all argument lists are empty
	if ctx.CommonArgs().Length() != 0 {
		t.Errorf("CommonArgs().Length() = %d, want 0", ctx.CommonArgs().Length())
	}
}

// TestToBuilder verifies AppContext.ToBuilder() creates mutable copy.
func TestToBuilder(t *testing.T) {
	// Create immutable context
	builder1 := NewAppContextBuilder("0.11.0")
	builder1.WorkspacePath = "/original/path"
	builder1.Verbose = true
	builder1.AppendCommonArg("--name", "test")
	ctx := builder1.Build()

	// Convert to builder
	builder2 := ctx.ToBuilder()

	// Verify builder has same values
	if builder2.WorkspacePath != "/original/path" {
		t.Errorf("builder2.WorkspacePath = %q, want %q", builder2.WorkspacePath, "/original/path")
	}
	if builder2.Verbose != true {
		t.Errorf("builder2.Verbose = %v, want true", builder2.Verbose)
	}

	// Modify builder
	builder2.WorkspacePath = "/new/path"
	builder2.AppendCommonArg("--extra", "arg")

	// Verify original context unchanged
	if ctx.WorkspacePath() != "/original/path" {
		t.Errorf("ctx.WorkspacePath() = %q, want %q (should be immutable)", ctx.WorkspacePath(), "/original/path")
	}
	if ctx.CommonArgs().Length() != 2 {
		t.Errorf("ctx.CommonArgs().Length() = %d, want 2 (should be immutable)", ctx.CommonArgs().Length())
	}

	// Build new context from modified builder
	ctx2 := builder2.Build()
	if ctx2.WorkspacePath() != "/new/path" {
		t.Errorf("ctx2.WorkspacePath() = %q, want %q", ctx2.WorkspacePath(), "/new/path")
	}
	if ctx2.CommonArgs().Length() != 4 {
		t.Errorf("ctx2.CommonArgs().Length() = %d, want 4", ctx2.CommonArgs().Length())
	}
}

// TestContextImmutability verifies AppContext cannot be modified.
func TestContextImmutability(t *testing.T) {
	builder := NewAppContextBuilder("0.11.0")
	builder.WorkspacePath = "/original"
	builder.AppendCommonArg("--name", "test")

	ctx := builder.Build()

	// Get snapshots
	originalPath := ctx.WorkspacePath()
	originalArgs := ctx.CommonArgs()

	// Modify builder (should not affect context)
	builder.WorkspacePath = "/modified"
	builder.AppendCommonArg("--extra", "arg")

	// Verify context unchanged
	if ctx.WorkspacePath() != originalPath {
		t.Errorf("ctx.WorkspacePath() changed from %q to %q", originalPath, ctx.WorkspacePath())
	}
	if ctx.CommonArgs().Length() != originalArgs.Length() {
		t.Errorf("ctx.CommonArgs().Length() changed from %d to %d", originalArgs.Length(), ctx.CommonArgs().Length())
	}
}
