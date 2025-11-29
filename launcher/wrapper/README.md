# WorkSpaceBootstrapper

WorkSpaceBootstrapper is the stable entry point for using the [CodingBooth WorkSpace](https://github.com/NawaMan/WorkSpace) `workspace.sh`.

It does not contain WorkSpace script itself — instead, it reliably downloads, verifies, and launches the real `workspace.sh` tool inside your project.

The wrapper is intended to be stable so do not worry if you don't see much activity in this project. :-)

# Why the Bootstrapper Exists

The actual `workspace.sh` (from the WorkSpace project) evolves constantly.
Your workflow shouldn’t break when the tool changes — and you shouldn’t have to manually fetch updates.

The Bootstrapper solves this by being:

## ✔ Stable

This script rarely changes. It stays safe and dependable while the real WorkSpace tool updates independently.

## ✔ Self-contained

It does not auto-update itself and does not depend on the WorkSpace repo.
You can check it into any project and know it will behave the same.

## ✔ Responsible for verification

Before running WorkSpace, it ensures:
- The tool exists locally
- The SHA1 checksum matches
- The tool is newer than its checksum
- The correct version is downloaded when requested

If anything is missing or corrupted, the Bootstrapper tells you to run `workspace update`.
