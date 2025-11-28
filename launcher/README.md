# workspace – The WorkSpace Launcher

`workspace` is a polyglot launcher (Bash + PowerShell) that provides a unified command for managing WorkSpace-enabled project folders.

It acts as the entrypoint for your project’s tooling, and delegates to project-local scripts stored under `.workspace/`.

## What it does

- Works in Bash, Zsh, Git Bash, WSL, and PowerShell
- Determines whether the current folder is a WorkSpace project
  - **If it is:** Delegates all commands to `.workspace/wrapper.sh`
  - **If it’s not:** Warns the user and allows `workspace init` to initialize the folder

## Project Layout

When a folder is initialized, it looks like:

```text
<your-project>/
  workspace                # global launcher you installed in PATH
  .workspace/
      wrapper.sh           # project-local wrapper/manager
      tools/
          workspace.sh     # actual runner (Docker logic, etc.)
```

You only run:

```bash
workspace <command>
```

Everything else stays hidden under `.workspace/`.

## Call Chain Overview

A single command:

```bash
workspace <command>
```

flows through the following layers:

```text
workspace                       (global cross-shell launcher)
   ↓
.workspace/wrapper.sh           (project-local wrapper: versions, downloads, integrity checks)
   ↓
.workspace/tools/workspace.sh   (runner: docker logic, actual command implementation)
```

This simple chain guarantees:
- The global launcher stays stable
- The project wrapper manages versioning and upgrades -- also stay relatively stable
- The runner can evolve independently without breaking the launcher

## Using the Launcher

### 1. Initialize a WorkSpace project

Run this inside the folder you want to convert:

```bash
workspace init
```

This will:
- Create `.workspace/`
- Download `wrapper.sh`
- Prepare the project for WorkSpace commands

### 2. Run WorkSpace commands

Once initialized:

```bash
workspace help
workspace run
workspace build
workspace anything-else
```

All commands are forwarded to `.workspace/wrapper.sh`, which then calls the underlying `workspace.sh` runner.

### 3. If you run it outside a WorkSpace project

You get:

```text
This is not a WorkSpace project folder (missing .workspace/wrapper.sh).
Run 'workspace init' in this folder to initialize it.
```

Simple and clear.

## Windows Support

The `workspace` launcher:
- Runs natively in PowerShell
- Automatically invokes Git Bash to execute the Bash logic
- Requires Git Bash to be installed (included with Git for Windows)

## Upgrading

If you installed `workspace` via a package manager (Homebrew, apt, scoop, etc.), upgrade normally:

```bash
brew upgrade workspace
```

Project-local files are managed by `.workspace/wrapper.sh` and can evolve separately.

## Summary

`workspace` is your universal, cross-shell launcher that makes WorkSpace projects easy to initialize and use.
Just drop it into your PATH once, then use `workspace init` to prepare any project folder.