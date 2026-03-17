# Boscinator

A tool for building and testing open source projects in disposable Docker containers. See README.md for full documentation.

## Conventions

- All build commands run inside the container via `docker exec <container> bash -c '...'` — never install anything on the host
- Containers are disposable — always clean up when done
- The base image is minimal Ubuntu 24.04 — install language toolchains as needed per project
- Container names follow the pattern `bosc-<reponame>-<hash>`
- Use `./boscinate.sh <url>` to create containers and `./boscinate.sh --cleanup <name>` to remove them
