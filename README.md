# Boscinator

Boscinator spins up a disposable Docker container, clones an open source project into it, and uses Claude to automatically explore, install dependencies, build, and report the results. It was created to support [BOSC](https://www.open-bio.org/events/bosc/) (Bioinformatics Open Source Conference) software evaluation workflows.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (version 20.10 or later)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (for the `/boscinate` slash command)

The script runs preflight checks automatically: it verifies Docker is installed and running, checks the minimum version, and warns if Docker has less than 4 GB of memory available (common on Docker Desktop for macOS/Windows). It works on both Linux and macOS.

## Quick start

### Using the Claude Code slash command (recommended)

These instructions assume you are already running [Claude Code](https://docs.anthropic.com/en/docs/claude-code) from this project directory. From the Claude Code prompt, run:

```
/boscinate https://github.com/jqlang/jq
```

Claude will automatically:

1. Build the Docker base image (if needed) and create a container
2. Clone the repo and explore its structure
3. Detect the build system and install the required toolchain
4. Attempt to build the project (up to 3 retries)
5. Print a structured report with the results
6. Clean up the container

To keep the container running after the build for manual exploration:

```
/boscinate --keep https://github.com/jqlang/jq
```

Claude will skip cleanup and print instructions for entering the container.

### Using the shell script directly

```bash
# Create a container and clone a project into it
./boscinate.sh https://github.com/jqlang/jq

# Output:
#   BOSCINATOR_CONTAINER=bosc-jq-a1b2c3d4
#   BOSCINATOR_WORKDIR=/workspace/project

# Run commands inside the container
docker exec bosc-jq-a1b2c3d4 bash -c 'cd /workspace/project && ls'

# Clean up when done
./boscinate.sh --cleanup bosc-jq-a1b2c3d4

# Or use --keep to get an interactive container with entry instructions
./boscinate.sh --keep https://github.com/jqlang/jq

# Then enter it with:
docker exec -it bosc-jq-a1b2c3d4 bash
```

## How it works

Boscinator uses a minimal Ubuntu 24.04 base image with only basic tools (git, curl, build-essential, etc.). No language-specific toolchains are pre-installed — they get added as needed for each project. This keeps the base image small and avoids version conflicts.

Each project gets its own isolated container named `bosc-<reponame>-<hash>`, capped at 4 GB of memory. Everything runs inside the container via `docker exec`, so nothing is installed on your host machine.

## File layout

| File | Purpose |
|------|---------|
| `Dockerfile` | Base Ubuntu 24.04 image definition |
| `boscinate.sh` | Container lifecycle script (create, clone, cleanup) |
| `.claude/commands/boscinate.md` | Claude Code slash command definition |
| `.claude/settings.local.json` | Pre-approved Docker permission patterns |
| `CLAUDE.md` | Project conventions for Claude Code |
