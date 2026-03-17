Boscinate: explore, build, and run an open source project in a disposable Docker container.

Input: $ARGUMENTS (a git URL, optionally preceded by `--keep`)

Parse the arguments: if `--keep` is present, set KEEP_CONTAINER=true, otherwise KEEP_CONTAINER=false. The git URL is always the last argument.

Follow these steps:

## 1. Setup

Run `./boscinate.sh $ARGUMENTS` and parse the output for `BOSCINATOR_CONTAINER=<name>` and `BOSCINATOR_WORKDIR=<workdir>`. Save both values — use them in all subsequent `docker exec` commands.

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
## Boscinator Report

- **Project:** <name> (<url>)
- **Build system:** <detected build system>
- **Language:** <primary language>
- **Dependencies installed:** <list>
- **Build result:** SUCCESS / FAILURE
- **Steps executed:**
  1. <step>
  2. <step>
  ...
- **Issues encountered:** <any problems and how they were resolved, or "None">
- **Container:** <container-name> (kept running / cleaned up)
```

## 6. Cleanup

If KEEP_CONTAINER is true, skip cleanup and instead tell the user:

```
Container **<container-name>** is still running. To explore:

    docker exec -it <container-name> bash

The project is at /workspace/project inside the container.

When done, clean up with:

    ./boscinate.sh --cleanup <container-name>
```

If KEEP_CONTAINER is false, remove the container:

```
./boscinate.sh --cleanup <container-name>
```
