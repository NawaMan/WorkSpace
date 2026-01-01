// Package appctx provides centralized application context for workspace configuration and state.
//
// AppContext is an immutable snapshot (like List), AppContextBuilder is mutable (like AppendableList).
// Use ToBuilder() and Build() to convert between them.
package appctx

import "github.com/nawaman/workspace/src/pkg/ilist"

// AppContext is an immutable snapshot of workspace configuration and state.
type AppContext struct {
	// Version & Paths
	wsVersion     string
	scriptName    string
	scriptDir     string
	libDir        string
	prebuildRepo  string
	setupsDir     string
	workspacePath string
	projectName   string

	// User & Environment
	hostUID  string
	hostGID  string
	timezone string

	// Flags
	dryrun         bool
	verbose        bool
	keepalive      bool
	silenceBuild   bool
	daemon         bool
	doPull         bool
	localBuild     bool
	setConfigFile  bool
	hasNotebook    bool
	hasVscode      bool
	hasDesktop     bool
	dind           bool
	createdDindNet bool

	// Image Configuration
	dockerFile string
	imageName  string
	imageMode  string
	variant    string
	version    string

	// Container Configuration
	containerName    string
	workspacePort    string
	hostPort         string
	portGenerated    bool
	containerEnvFile string
	configFile       string
	fileNotUsed      string

	// Docker-in-Docker
	dindNet   string
	dindName  string
	dockerBin string

	// Runtime State
	runMode string

	// Argument Lists (immutable snapshots)
	commonArgs    ilist.List[string]
	buildArgs     ilist.List[string]
	runArgs       ilist.List[string]
	cmds          ilist.List[string]
	keepaliveArgs ilist.List[string]
	ttyArgs       ilist.List[string]
}

// NewAppContext creates a new immutable AppContext with defaults matching workspace.sh initialization.
func NewAppContext(wsVersion string) AppContext {
	return AppContext{
		// Version & Paths
		wsVersion:    wsVersion,
		prebuildRepo: "nawaman/workspace",
		fileNotUsed:  "none",
		setupsDir:    "/opt/workspace/setups",

		// Flags
		dryrun:       false,
		verbose:      false,
		keepalive:    false,
		silenceBuild: false,
		daemon:       false,
		doPull:       false,
		localBuild:   false,
		hasNotebook:  false,
		hasVscode:    false,
		hasDesktop:   false,
		dind:         false,

		// Image Configuration
		variant: "default",
		version: "latest",

		// Container Configuration
		workspacePort: "NEXT",

		// Initialize empty snapshots
		commonArgs:    ilist.NewList[string](),
		buildArgs:     ilist.NewList[string](),
		runArgs:       ilist.NewList[string](),
		cmds:          ilist.NewList[string](),
		keepaliveArgs: ilist.NewList[string](),
		ttyArgs:       ilist.NewList[string](),
	}
}

// ToBuilder creates a mutable AppContextBuilder with a copy of this AppContext's data.
func (ctx AppContext) ToBuilder() *AppContextBuilder {
	return &AppContextBuilder{
		// Version & Paths
		WsVersion:     ctx.wsVersion,
		ScriptName:    ctx.scriptName,
		ScriptDir:     ctx.scriptDir,
		LibDir:        ctx.libDir,
		PrebuildRepo:  ctx.prebuildRepo,
		SetupsDir:     ctx.setupsDir,
		WorkspacePath: ctx.workspacePath,
		ProjectName:   ctx.projectName,

		// User & Environment
		HostUID:  ctx.hostUID,
		HostGID:  ctx.hostGID,
		Timezone: ctx.timezone,

		// Flags
		Dryrun:         ctx.dryrun,
		Verbose:        ctx.verbose,
		Keepalive:      ctx.keepalive,
		SilenceBuild:   ctx.silenceBuild,
		Daemon:         ctx.daemon,
		DoPull:         ctx.doPull,
		LocalBuild:     ctx.localBuild,
		SetConfigFile:  ctx.setConfigFile,
		HasNotebook:    ctx.hasNotebook,
		HasVscode:      ctx.hasVscode,
		HasDesktop:     ctx.hasDesktop,
		Dind:           ctx.dind,
		CreatedDindNet: ctx.createdDindNet,

		// Image Configuration
		DockerFile: ctx.dockerFile,
		ImageName:  ctx.imageName,
		ImageMode:  ctx.imageMode,
		Variant:    ctx.variant,
		Version:    ctx.version,

		// Container Configuration
		ContainerName:    ctx.containerName,
		WorkspacePort:    ctx.workspacePort,
		HostPort:         ctx.hostPort,
		PortGenerated:    ctx.portGenerated,
		ContainerEnvFile: ctx.containerEnvFile,
		ConfigFile:       ctx.configFile,
		FileNotUsed:      ctx.fileNotUsed,

		// Docker-in-Docker
		DindNet:   ctx.dindNet,
		DindName:  ctx.dindName,
		DockerBin: ctx.dockerBin,

		// Runtime State
		RunMode: ctx.runMode,

		// Argument Lists (convert to mutable builders)
		CommonArgs:    ctx.commonArgs.ToBuilder(),
		BuildArgs:     ctx.buildArgs.ToBuilder(),
		RunArgs:       ctx.runArgs.ToBuilder(),
		Cmds:          ctx.cmds.ToBuilder(),
		KeepaliveArgs: ctx.keepaliveArgs.ToBuilder(),
		TtyArgs:       ctx.ttyArgs.ToBuilder(),
	}
}

// Getters for Version & Paths
func (ctx AppContext) WsVersion() string     { return ctx.wsVersion }
func (ctx AppContext) ScriptName() string    { return ctx.scriptName }
func (ctx AppContext) ScriptDir() string     { return ctx.scriptDir }
func (ctx AppContext) LibDir() string        { return ctx.libDir }
func (ctx AppContext) PrebuildRepo() string  { return ctx.prebuildRepo }
func (ctx AppContext) SetupsDir() string     { return ctx.setupsDir }
func (ctx AppContext) WorkspacePath() string { return ctx.workspacePath }
func (ctx AppContext) ProjectName() string   { return ctx.projectName }

// Getters for User & Environment
func (ctx AppContext) HostUID() string  { return ctx.hostUID }
func (ctx AppContext) HostGID() string  { return ctx.hostGID }
func (ctx AppContext) Timezone() string { return ctx.timezone }

// Getters for Flags
func (ctx AppContext) Dryrun() bool           { return ctx.dryrun }
func (ctx AppContext) Verbose() bool          { return ctx.verbose }
func (ctx AppContext) Keepalive() bool        { return ctx.keepalive }
func (ctx AppContext) SilenceBuild() bool     { return ctx.silenceBuild }
func (ctx AppContext) Daemon() bool           { return ctx.daemon }
func (ctx AppContext) DoPull() bool           { return ctx.doPull }
func (ctx AppContext) LocalBuild() bool       { return ctx.localBuild }
func (ctx AppContext) GetSetConfigFile() bool { return ctx.setConfigFile }
func (ctx AppContext) HasNotebook() bool      { return ctx.hasNotebook }
func (ctx AppContext) HasVscode() bool        { return ctx.hasVscode }
func (ctx AppContext) HasDesktop() bool       { return ctx.hasDesktop }
func (ctx AppContext) Dind() bool             { return ctx.dind }
func (ctx AppContext) CreatedDindNet() bool   { return ctx.createdDindNet }

// Getters for Image Configuration
func (ctx AppContext) DockerFile() string { return ctx.dockerFile }
func (ctx AppContext) ImageName() string  { return ctx.imageName }
func (ctx AppContext) ImageMode() string  { return ctx.imageMode }
func (ctx AppContext) Variant() string    { return ctx.variant }
func (ctx AppContext) Version() string    { return ctx.version }

// Getters for Container Configuration
func (ctx AppContext) ContainerName() string    { return ctx.containerName }
func (ctx AppContext) WorkspacePort() string    { return ctx.workspacePort }
func (ctx AppContext) HostPort() string         { return ctx.hostPort }
func (ctx AppContext) PortGenerated() bool      { return ctx.portGenerated }
func (ctx AppContext) ContainerEnvFile() string { return ctx.containerEnvFile }
func (ctx AppContext) ConfigFile() string       { return ctx.configFile }
func (ctx AppContext) FileNotUsed() string      { return ctx.fileNotUsed }

// Getters for Docker-in-Docker
func (ctx AppContext) DindNet() string   { return ctx.dindNet }
func (ctx AppContext) DindName() string  { return ctx.dindName }
func (ctx AppContext) DockerBin() string { return ctx.dockerBin }

// Getters for Runtime State
func (ctx AppContext) RunMode() string { return ctx.runMode }

// Getters for Argument Lists (return immutable snapshots)
func (ctx AppContext) CommonArgs() ilist.List[string]    { return ctx.commonArgs }
func (ctx AppContext) BuildArgs() ilist.List[string]     { return ctx.buildArgs }
func (ctx AppContext) RunArgs() ilist.List[string]       { return ctx.runArgs }
func (ctx AppContext) Cmds() ilist.List[string]          { return ctx.cmds }
func (ctx AppContext) KeepAliveArgs() ilist.List[string] { return ctx.keepaliveArgs }
func (ctx AppContext) TtyArgs() ilist.List[string]       { return ctx.ttyArgs }
