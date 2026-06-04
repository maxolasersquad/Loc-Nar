# Loc-Nar Project Context

## Overview
Loc-Nar is a repository of **package definitions** (Loc-Nars) for the [Taarak (trk)](/home/maxolasersquad/code/taarak) application version manager. It provides a standardized interface for `trk` to automate the installation, versioning, and switching of various CLI utilities.

## Directory Structure
The project is organized into subdirectories, where each directory name corresponds to a package name in `trk`.
Example tools included:
- `lazygit`: TUI front-end for Git.
- `lsd`: Modern replacement for `ls`.
- `obsidian-cli`: CLI tool for managing Obsidian vaults.
- `opencode`: AI-powered terminal coding agent.
- `signal-cli`: CLI for Signal messenger.

### Tool Subdirectory Interface (Taarak Contract)
Each tool directory MUST contain the following executable POSIX shell scripts:

- **`description.sh`**: Prints a brief, often stylized (ANSI colors/links) description of the tool.
- **`versions.sh`**: Prints a newline-separated list of available version strings (ideally newest first).
- **`install.sh`**: Handles download, extraction, and building. 
  - **Output**: MUST print ONLY the **relative path** to the main executable within the installation directory on success.
- **`switch.sh`**: Handles package-specific activation steps.
  - **Output**: MUST print the **absolute path** to the main executable for the requested version on success.
- **`uninstall.sh`**: Performs cleanup tasks (e.g., config files) outside the version directory.

## Development Conventions

### Script Standards
- **Shell**: All scripts must be strictly POSIX-compliant (`#!/bin/sh`).
- **Linting**: Scripts should pass `shellcheck`. Configuration is defined in `.shellcheckrc`.
- **Arguments**:
  - `--location <path>`: (Required) Target directory for installation or lookup.
  - `--version <tag>`: (Required) The specific version to act upon.
  - `--verbose`: Enable detailed logging to stderr.
  - `--source`: (Optional for `install.sh`) Build from source instead of using pre-compiled binaries.

### Error Handling & Logging
- Log informational/verbose messages to `stderr`.
- Return non-zero exit codes on failure:
  - `2`: Invalid or non-existent version.
  - `3`: Download failure.
  - `4`: Extraction failure.
  - `5`: Build failure.
  - `6`: Missing dependency (e.g., `curl`, `jq`, `go`).
  - `7`: Filesystem/Permission issues.

## Integration with Taarak
To use these definitions with `trk`, they should be linked or copied into one of Taarak's Loc-Nar search paths:
- **Local**: `~/.local/share/trk/locnar/`
- **Global**: `/usr/local/share/trk/locnar/`

Example:
```bash
ln -s $(pwd)/lazygit ~/.local/share/trk/locnar/lazygit
```

