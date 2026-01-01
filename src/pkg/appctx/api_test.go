package appctx

import (
	"testing"

	"github.com/nawaman/workspace/src/pkg/ilist"
)

// TestRoundTrip verifies AppContext → Builder → AppContext preserves data.
func TestRoundTrip(t *testing.T) {
	// Create original context
	builder := NewAppContextBuilder("0.11.0")
	builder.WorkspacePath = "/test/workspace"
	builder.ContainerName = "my-container"
	builder.Verbose = true
	builder.Dryrun = false
	builder.AppendCommonArg("--name", "test")
	builder.AppendCommonArg("-v", "/workspace:/workspace")
	builder.AppendBuildArg("--build-arg", "FOO=bar")

	ctx1 := builder.Build()

	// Round trip: Context → Builder → Context
	ctx2 := ctx1.ToBuilder().Build()

	// Verify all values preserved
	if ctx2.WorkspacePath() != ctx1.WorkspacePath() {
		t.Errorf("WorkspacePath mismatch: %q != %q", ctx2.WorkspacePath(), ctx1.WorkspacePath())
	}
	if ctx2.ContainerName() != ctx1.ContainerName() {
		t.Errorf("ContainerName mismatch: %q != %q", ctx2.ContainerName(), ctx1.ContainerName())
	}
	if ctx2.Verbose() != ctx1.Verbose() {
		t.Errorf("Verbose mismatch: %v != %v", ctx2.Verbose(), ctx1.Verbose())
	}
	if ctx2.CommonArgs().Length() != ctx1.CommonArgs().Length() {
		t.Errorf("CommonArgs length mismatch: %d != %d", ctx2.CommonArgs().Length(), ctx1.CommonArgs().Length())
	}
	if ctx2.BuildArgs().Length() != ctx1.BuildArgs().Length() {
		t.Errorf("BuildArgs length mismatch: %d != %d", ctx2.BuildArgs().Length(), ctx1.BuildArgs().Length())
	}
}

// TestDockerArgsWorkflow simulates the Docker args building workflow from workspace.sh.
func TestDockerArgsWorkflow(t *testing.T) {
	builder := NewAppContextBuilder("0.11.0")

	// Simulate PrepareCommonArgs from workspace.sh (lines 691-720)
	builder.ContainerName = "test-workspace"
	builder.HostUID = "1000"
	builder.HostGID = "1000"
	builder.WorkspacePath = "/home/user/workspace"
	builder.HostPort = "10000"

	builder.AppendCommonArg("--name", builder.ContainerName)
	builder.AppendCommonArg("-e", "HOST_UID="+builder.HostUID)
	builder.AppendCommonArg("-e", "HOST_GID="+builder.HostGID)
	builder.AppendCommonArg("-v", builder.WorkspacePath+":/home/coder/workspace")
	builder.AppendCommonArg("-w", "/home/coder/workspace")
	builder.AppendCommonArg("-p", builder.HostPort+":10000")

	// Build immutable context
	ctx := builder.Build()

	// Verify common args
	commonArgs := ctx.CommonArgs()
	if commonArgs.Length() != 12 {
		t.Errorf("commonArgs.Length() = %d, want 12", commonArgs.Length())
	}

	// Verify specific args
	slice := commonArgs.Slice()
	if slice[0] != "--name" || slice[1] != "test-workspace" {
		t.Errorf("Expected --name test-workspace, got %v %v", slice[0], slice[1])
	}

	// Simulate PrepareKeepAliveArgs (lines 722-727)
	builder.Keepalive = false
	if !builder.Keepalive {
		builder.KeepaliveArgs = ilist.NewAppendableListFrom("--rm")
	}

	ctx = builder.Build()
	keepaliveArgs := ctx.KeepAliveArgs()
	if keepaliveArgs.Length() != 1 {
		t.Errorf("keepaliveArgs.Length() = %d, want 1", keepaliveArgs.Length())
	}
	if val, ok := keepaliveArgs.Get(0); !ok || val != "--rm" {
		t.Errorf("keepaliveArgs.Get(0) = %q, want %q", val, "--rm")
	}
}

// TestListExtension verifies extending lists with ilist operations.
func TestListExtension(t *testing.T) {
	builder := NewAppContextBuilder("0.11.0")

	// Build initial args
	builder.AppendCommonArg("--name", "test")
	ctx := builder.Build()

	// Get snapshot and extend it
	baseArgs := ctx.CommonArgs()
	extraArgs := ilist.NewList("--extra", "value")
	combined := baseArgs.ExtendByLists(extraArgs)

	// Verify combined list
	if combined.Length() != 4 {
		t.Errorf("combined.Length() = %d, want 4", combined.Length())
	}

	// Verify original snapshot unchanged
	if baseArgs.Length() != 2 {
		t.Errorf("baseArgs.Length() = %d, want 2 (should be immutable)", baseArgs.Length())
	}
}
