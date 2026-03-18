# Runabilly

A tool for building and testing open source projects in disposable Docker containers. See README.md for full documentation.

## Conventions

- All build commands run inside the container via `docker exec <container> bash -c '...'` — never install anything on the host
- Containers are disposable — always clean up when done
- The base image is minimal Ubuntu 24.04 — install language toolchains as needed per project
- Container names follow the pattern `runa-<reponame>-<hash>`
- Use `./runabilly.sh <url>` to create containers and `./runabilly.sh --cleanup <name>` to remove them
- Use `./runabilly.sh --keep <url>` to keep the container running after setup for manual exploration
- The script runs cross-platform preflight checks (Docker installed/running, version >= 20.10, memory warning)
