package appctx

import "github.com/nawaman/workspace/src/pkg/ilist"

// AppContextBuilder is a mutable builder for constructing AppContext instances.
// All fields are public for direct access.
type AppContextBuilder struct {
	// Version & Paths
	WsVersion     string
	ScriptName    string
	ScriptDir     string
	LibDir        string
	PrebuildRepo  string
	SetupsDir     string
	WorkspacePath string
	ProjectName   string

	// User & Environment
	HostUID  string
	HostGID  string
	Timezone string

	// Flags
	Dryrun         bool
	Verbose        bool
	Keepalive      bool
	SilenceBuild   bool
	Daemon         bool
	DoPull         bool
	LocalBuild     bool
	SetConfigFile  bool
	HasNotebook    bool
	HasVscode      bool
	HasDesktop     bool
	Dind           bool
	CreatedDindNet bool

	// Image Configuration
	DockerFile string
	ImageName  string
	ImageMode  string
	Variant    string
	Version    string

	// Container Configuration
	ContainerName    string
	WorkspacePort    string
	HostPort         string
	PortGenerated    bool
	ContainerEnvFile string
	ConfigFile       string
	FileNotUsed      string

	// Docker-in-Docker
	DindNet   string
	DindName  string
	DockerBin string

	// Runtime State
	RunMode string

	// Argument Lists (mutable builders)
	CommonArgs    *ilist.AppendableList[string]
	BuildArgs     *ilist.AppendableList[string]
	RunArgs       *ilist.AppendableList[string]
	Cmds          *ilist.AppendableList[string]
	KeepaliveArgs *ilist.AppendableList[string]
	TtyArgs       *ilist.AppendableList[string]
}

// NewAppContextBuilder creates a new AppContextBuilder with defaults matching workspace.sh initialization.
func NewAppContextBuilder(wsVersion string) *AppContextBuilder {
	return &AppContextBuilder{
		// Version & Paths
		WsVersion:    wsVersion,
		PrebuildRepo: "nawaman/workspace",
		FileNotUsed:  "none",
		SetupsDir:    "/opt/workspace/setups",

		// Flags
		Dryrun:       false,
		Verbose:      false,
		Keepalive:    false,
		SilenceBuild: false,
		Daemon:       false,
		DoPull:       false,
		LocalBuild:   false,
		HasNotebook:  false,
		HasVscode:    false,
		HasDesktop:   false,
		Dind:         false,

		// Image Configuration
		Variant: "default",
		Version: "latest",

		// Container Configuration
		WorkspacePort: "NEXT",

		// Initialize builders
		CommonArgs:    ilist.NewAppendableList[string](),
		BuildArgs:     ilist.NewAppendableList[string](),
		RunArgs:       ilist.NewAppendableList[string](),
		Cmds:          ilist.NewAppendableList[string](),
		KeepaliveArgs: ilist.NewAppendableList[string](),
		TtyArgs:       ilist.NewAppendableList[string](),
	}
}

// Build creates an immutable AppContext snapshot from this builder.
func (builder *AppContextBuilder) Build() AppContext {
	return AppContext{
		// Version & Paths
		wsVersion:     builder.WsVersion,
		scriptName:    builder.ScriptName,
		scriptDir:     builder.ScriptDir,
		libDir:        builder.LibDir,
		prebuildRepo:  builder.PrebuildRepo,
		setupsDir:     builder.SetupsDir,
		workspacePath: builder.WorkspacePath,
		projectName:   builder.ProjectName,

		// User & Environment
		hostUID:  builder.HostUID,
		hostGID:  builder.HostGID,
		timezone: builder.Timezone,

		// Flags
		dryrun:         builder.Dryrun,
		verbose:        builder.Verbose,
		keepalive:      builder.Keepalive,
		silenceBuild:   builder.SilenceBuild,
		daemon:         builder.Daemon,
		doPull:         builder.DoPull,
		localBuild:     builder.LocalBuild,
		setConfigFile:  builder.SetConfigFile,
		hasNotebook:    builder.HasNotebook,
		hasVscode:      builder.HasVscode,
		hasDesktop:     builder.HasDesktop,
		dind:           builder.Dind,
		createdDindNet: builder.CreatedDindNet,

		// Image Configuration
		dockerFile: builder.DockerFile,
		imageName:  builder.ImageName,
		imageMode:  builder.ImageMode,
		variant:    builder.Variant,
		version:    builder.Version,

		// Container Configuration
		containerName:    builder.ContainerName,
		workspacePort:    builder.WorkspacePort,
		hostPort:         builder.HostPort,
		portGenerated:    builder.PortGenerated,
		containerEnvFile: builder.ContainerEnvFile,
		configFile:       builder.ConfigFile,
		fileNotUsed:      builder.FileNotUsed,

		// Docker-in-Docker
		dindNet:   builder.DindNet,
		dindName:  builder.DindName,
		dockerBin: builder.DockerBin,

		// Runtime State
		runMode: builder.RunMode,

		// Argument Lists (snapshot to immutable)
		commonArgs:    builder.CommonArgs.Snapshot(),
		buildArgs:     builder.BuildArgs.Snapshot(),
		runArgs:       builder.RunArgs.Snapshot(),
		cmds:          builder.Cmds.Snapshot(),
		keepaliveArgs: builder.KeepaliveArgs.Snapshot(),
		ttyArgs:       builder.TtyArgs.Snapshot(),
	}
}

// Helper methods for appending to argument lists (for convenience)

// AppendCommonArg adds arguments to the common args builder.
func (builder *AppContextBuilder) AppendCommonArg(args ...string) {
	builder.CommonArgs.Append(args...)
}

// AppendBuildArg adds arguments to the build args builder.
func (builder *AppContextBuilder) AppendBuildArg(args ...string) {
	builder.BuildArgs.Append(args...)
}

// AppendRunArg adds arguments to the run args builder.
func (builder *AppContextBuilder) AppendRunArg(args ...string) {
	builder.RunArgs.Append(args...)
}

// AppendCmd adds commands to the cmds builder.
func (builder *AppContextBuilder) AppendCmd(cmds ...string) {
	builder.Cmds.Append(cmds...)
}
