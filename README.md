# Loc-Nar Development Guide

This repository contains **Loc-Nars** (package definitions) for the [Taarak (trk)](https://github.com/maxolasersquad/taarak) version manager. A Loc-Nar is a directory containing a specific set of scripts that teach `trk` how to manage a particular application.

## Core Philosophy

1.  **Strict POSIX Compliance:** All scripts MUST be written in pure POSIX shell (`#!/bin/sh`). Avoid Bash-specific features (bashisms) like `local`, `source`, `[[ ]]`, or arrays.
2.  **Delegated Responsibility:** `trk` handles the directory structure and symlinking; the Loc-Nar handles the tool-specific download, build, and path resolution.
3.  **Statelessness:** Loc-Nars should not store state internally. They react to the arguments (`--location`, `--version`) provided by `trk`.

## Directory Structure

Each package is a folder in the root of this repository:
```text
loc-nar/
└── <package-name>/
    ├── description.sh
    ├── versions.sh
    ├── install.sh
    ├── switch.sh
    └── uninstall.sh
```

## The Script Contract

### 1. `description.sh`
Prints a one-line description of the tool.
*   **Output:** Plain text or ANSI-stylized string.
*   **Example:** `printf 'A modern replacement for ls.\n'`

### 2. `versions.sh`
Lists available versions for the tool.
*   **Output:** Newline-separated strings.
*   **Best Practice:** List versions in descending order (newest first) to help `trk` identify the "latest" version using simple sort logic.

### 3. `install.sh`
Downloads and installs the tool into the provided `--location`.
*   **Arguments:** `--location`, `--version`, `--verbose`, `--source`.
*   **Contract:** On success (exit 0), it **MUST** print ONLY the **relative path** to the main executable from the root of the installation directory.
*   **Source Support:** If `--source` is passed, the script should attempt to build from source rather than downloading a binary.

### 4. `switch.sh`
Resolves the executable path and performs any activation logic.
*   **Arguments:** `--location`, `--version`, `--verbose`.
*   **Contract:** On success (exit 0), it **MUST** print the **absolute path** to the main executable.

### 5. `uninstall.sh`
Performs cleanup *outside* the version directory (e.g., removing shared config or cache).
*   **Arguments:** `--location`, `--verbose`.
*   **Note:** `trk` handles the deletion of the version directory itself.

---

## Development Standards

### POSIX Implementation Rules
To ensure maximum portability, follow these rules:
*   **No `local`:** Use unique variable names or subshells `( ... )`.
*   **No `source`:** Use the dot operator: `. ./script.sh`.
*   **No `which`:** Use `command -v tool_name` for dependency checks.
*   **No `[[`:** Use standard `[ ]` or `test`.
*   **Portable Sed/Awk:** Stick to basic features supported by BusyBox/BSD versions.

### Standard Arguments
All scripts should handle these standard flags via a `while` loop:
*   `--location=PATH` or `--location PATH`: The directory to act within.
*   `--version=VER` or `--version VER`: The version string to target.
*   `--verbose`: Enable logging to `stderr`.
*   `--source`: (Specific to `install.sh`) Toggle build-from-source mode.

### Error Handling
Scripts must use `stderr` for logging and return standardized exit codes:
*   `0`: Success.
*   `2`: Invalid version specified.
*   `3`: Download failure.
*   `4`: Extraction/Archive failure.
*   `5`: Build/Compilation failure.
*   `6`: Missing dependency (e.g., `jq`, `curl`).
*   `7`: Filesystem or Permission error.

### Dependencies
Loc-Nars should be as lightweight as possible. Standard allowed dependencies include:
*   `curl` or `wget` (for networking).
*   `jq` (for JSON API parsing).
*   `tar`, `gzip`, `unzip` (for extraction).
*   `sed`, `awk`, `grep` (for text processing).

## Linting
All scripts must pass `shellcheck`. A `.shellcheckrc` is provided in the root to enforce POSIX rules (`shell=sh`).

```bash
shellcheck <package-name>/*.sh
```
