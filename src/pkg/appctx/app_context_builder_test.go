package appctx

import (
	"testing"
)

// TestNewAppContextBuilder verifies builder constructor initializes defaults.
func TestNewAppContextBuilder(t *testing.T) {
	builder := NewAppContextBuilder("0.11.0")

	if builder.WsVersion != "0.11.0" {
		t.Errorf("WsVersion = %q, want %q", builder.WsVersion, "0.11.0")
	}
	if builder.Variant != "default" {
		t.Errorf("Variant = %q, want %q", builder.Variant, "default")
	}
}

// TestBuilderPattern verifies builder methods work correctly.
func TestBuilderPattern(t *testing.T) {
	builder := NewAppContextBuilder("0.11.0")

	// Append to builders
	builder.AppendCommonArg("--name", "test-container")
	builder.AppendCommonArg("-v", "/workspace:/workspace")
	builder.AppendBuildArg("--build-arg", "FOO=bar")
	builder.AppendRunArg("--env", "TEST=1")
	builder.AppendCmd("bash", "-c", "echo hello")

	// Build immutable snapshot
	ctx := builder.Build()

	// Verify snapshots
	commonArgs := ctx.CommonArgs()
	if commonArgs.Length() != 4 {
		t.Errorf("CommonArgs().Length() = %d, want 4", commonArgs.Length())
	}
	if val, ok := commonArgs.Get(0); !ok || val != "--name" {
		t.Errorf("CommonArgs().Get(0) = %q, want %q", val, "--name")
	}
	if val, ok := commonArgs.Get(1); !ok || val != "test-container" {
		t.Errorf("CommonArgs().Get(1) = %q, want %q", val, "test-container")
	}

	buildArgs := ctx.BuildArgs()
	if buildArgs.Length() != 2 {
		t.Errorf("BuildArgs().Length() = %d, want 2", buildArgs.Length())
	}

	runArgs := ctx.RunArgs()
	if runArgs.Length() != 2 {
		t.Errorf("RunArgs().Length() = %d, want 2", runArgs.Length())
	}

	cmds := ctx.Cmds()
	if cmds.Length() != 3 {
		t.Errorf("Cmds().Length() = %d, want 3", cmds.Length())
	}
}

// TestBuildImmutability verifies Build() creates immutable snapshots.
func TestBuildImmutability(t *testing.T) {
	builder := NewAppContextBuilder("0.11.0")

	// Build and get snapshot
	builder.AppendCommonArg("--name", "original")
	ctx := builder.Build()

	snapshot := ctx.CommonArgs()
	if snapshot.Length() != 2 {
		t.Fatalf("snapshot.Length() = %d, want 2", snapshot.Length())
	}

	// Modify builder after Build()
	builder.AppendCommonArg("--extra", "arg")
	builder.AppendCommonArg("--more", "stuff")

	// Verify original snapshot unchanged
	if snapshot.Length() != 2 {
		t.Errorf("snapshot.Length() = %d, want 2 (snapshot should be immutable)", snapshot.Length())
	}
	if val, ok := snapshot.Get(0); !ok || val != "--name" {
		t.Errorf("snapshot.Get(0) = %q, want %q", val, "--name")
	}
	if val, ok := snapshot.Get(1); !ok || val != "original" {
		t.Errorf("snapshot.Get(1) = %q, want %q", val, "original")
	}

	// Verify new build has all values
	ctx2 := builder.Build()
	newSnapshot := ctx2.CommonArgs()
	if newSnapshot.Length() != 6 {
		t.Errorf("newSnapshot.Length() = %d, want 6", newSnapshot.Length())
	}
}

// TestSetters verifies all setter methods work correctly on builder.
func TestSetters(t *testing.T) {
	builder := NewAppContextBuilder("0.11.0")

	// Test direct field access
	builder.ScriptName = "test.sh"
	if builder.ScriptName != "test.sh" {
		t.Errorf("ScriptName = %q, want %q", builder.ScriptName, "test.sh")
	}

	builder.WorkspacePath = "/test/workspace"
	if builder.WorkspacePath != "/test/workspace" {
		t.Errorf("WorkspacePath = %q, want %q", builder.WorkspacePath, "/test/workspace")
	}

	builder.ImageName = "test-image:latest"
	if builder.ImageName != "test-image:latest" {
		t.Errorf("ImageName = %q, want %q", builder.ImageName, "test-image:latest")
	}

	// Test bool fields
	builder.Verbose = true
	if builder.Verbose != true {
		t.Errorf("Verbose = %v, want true", builder.Verbose)
	}

	builder.Dryrun = true
	if builder.Dryrun != true {
		t.Errorf("Dryrun = %v, want true", builder.Dryrun)
	}

	builder.Daemon = true
	if builder.Daemon != true {
		t.Errorf("Daemon = %v, want true", builder.Daemon)
	}
}
