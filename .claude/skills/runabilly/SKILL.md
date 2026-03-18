---
name: runabilly
description: Explore, build, and run an open source project in a disposable Docker container
disable-model-invocation: true
---

Runabilly: explore, build, and run an open source project in a disposable Docker container.

Input: $ARGUMENTS (a git URL, optionally preceded by `--keep`)

Parse the arguments: if `--keep` is present, set KEEP_CONTAINER=true, otherwise KEEP_CONTAINER=false. The git URL is always the last argument.

**Timeout:** The entire evaluation (setup through build) must complete within 1 hour. Record the start time at the beginning. Before each build attempt, check elapsed time. If 1 hour has passed, stop immediately, clean up the container, and report the build result as FAILURE with "Timed out after 1 hour" in issues encountered.

Follow these steps:

## 1. Setup

Run `./runabilly.sh $ARGUMENTS` and parse the output for `RUNABILLY_CONTAINER=<name>` and `RUNABILLY_WORKDIR=<workdir>`. Save both values — use them in all subsequent `docker exec` commands.

If setup fails, report the error and stop.

## 2. Explore

Run these inside the container to understand the project:

```
docker exec <container> bash -c 'ls -la /workspace/project/'
docker exec <container> bash -c 'cat /workspace/project/README.md 2>/dev/null || echo "No README found"'
docker exec <container> bash -c 'ls /workspace/project/Makefile /workspace/project/CMakeLists.txt /workspace/project/setup.py /workspace/project/pyproject.toml /workspace/project/package.json /workspace/project/Cargo.toml /workspace/project/go.mod /workspace/project/pom.xml /workspace/project/build.gradle /workspace/project/configure /workspace/project/configure.ac /workspace/project/meson.build 2>/dev/null || echo "No standard build files found"'
```

Identify the build system and language from the files present.

## 3. Install

Based on what you discovered, install the required toolchain inside the container. Examples:

- **C/C++ (autotools):** `apt-get update && apt-get install -y autoconf automake libtool`
- **C/C++ (cmake):** `apt-get update && apt-get install -y cmake`
- **Python:** `apt-get update && apt-get install -y python3 python3-pip python3-venv`
- **Node.js:** `curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && apt-get install -y nodejs`
- **Rust:** `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y`
- **Go:** `apt-get update && apt-get install -y golang-go`
- **Java (Maven):** `apt-get update && apt-get install -y default-jdk maven`

Install any additional dependencies mentioned in the README or build files.

All installs run via: `docker exec <container> bash -c '...'`

## 4. Build

Attempt to build the project following the discovered instructions. Common patterns:

- **autotools:** `autoreconf -i && ./configure && make`
- **cmake:** `mkdir build && cd build && cmake .. && make`
- **make:** `make`
- **python:** `pip install -e .` or `python setup.py build`
- **npm:** `npm install && npm run build`
- **cargo:** `cargo build`
- **go:** `go build ./...`

Run the build commands inside the container:
```
docker exec <container> bash -c 'cd /workspace/project && <build-commands>'
```

If the build fails, read the error output, try to diagnose and fix (install missing deps, adjust commands), and retry. Make up to 3 attempts.

## 5. Report

Output a structured summary:

```
## Runabilly Report

- **Project:** <name> (<url>)
- **Build system:** <detected build system>
- **Language:** <primary language>
- **Dependencies installed:** <list>
- **Build result:** SUCCESS / WARNING / FAILURE / UNDEFINED
  - SUCCESS: builds and/or tests pass
  - WARNING: builds partially but full validation blocked by a high hurdle (e.g. Docker-in-Docker, large external databases, requires paid API keys)
  - FAILURE: build fails after retries
  - UNDEFINED: URL isn't a buildable repo (e.g. Kaggle homepage, documentation site, dataset collection)
- **Steps executed:**
  1. <step>
  2. <step>
  ...
- **Issues encountered:** <any problems and how they were resolved, or "None">
- **Difficulty:** <EASY / MODERATE / HARD / IMPRACTICAL>
  - Time: <LOW / MEDIUM / HIGH> — LOW: < 60s, MEDIUM: 60s–300s, HIGH: > 300s (wall-clock build time)
  - Dependencies: <LOW / MEDIUM / HIGH> — LOW: < 10 packages, MEDIUM: 10–50, HIGH: > 50 or multiple toolchains
  - Exoticness: <LOW / MEDIUM / HIGH> — LOW: standard build system, no workarounds; MEDIUM: less common build system or minor workarounds; HIGH: custom scripts, multi-stage setup, Docker-in-Docker, etc.
  - Divergence: <LOW / MEDIUM / HIGH> — LOW: documented build path worked on first try; MEDIUM: minor adjustments needed (missing dep, flag tweak); HIGH: documented path failed and alternate route required, or no docs at all
  - Roll-up: EASY = all LOW; MODERATE = any MEDIUM, no HIGH; HARD = any HIGH; IMPRACTICAL = can't realistically complete in a disposable container
- **Container:** <container-name> (kept running / cleaned up)
```

## 6. Cleanup

If KEEP_CONTAINER is true, skip cleanup and instead tell the user:

```
Container **<container-name>** is still running. To explore:

    docker exec -it <container-name> bash

The project is at /workspace/project inside the container.

When done, clean up with:

    ./runabilly.sh --cleanup <container-name>
```

If KEEP_CONTAINER is false, remove the container:

```
./runabilly.sh --cleanup <container-name>
```
