#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="runabilly-base"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIN_DOCKER_VERSION="20.10"

usage() {
    echo "Usage: $0 [--keep] <git-url>"
    echo "       $0 --cleanup <container-name>"
    echo ""
    echo "Options:"
    echo "  --keep    Keep the container running after setup for manual exploration"
    echo "  --cleanup Remove a previously created container"
    exit 1
}

# Cross-platform md5 hash (Linux: md5sum, macOS: md5)
portable_md5() {
    if command -v md5sum &>/dev/null; then
        md5sum | cut -c1-8
    elif command -v md5 &>/dev/null; then
        md5 | cut -c1-8
    else
        echo "Error: No md5sum or md5 command found" >&2
        exit 1
    fi
}

# Compare two version strings; returns 0 if $1 >= $2
version_gte() {
    local IFS=.
    local i a=($1) b=($2)
    for ((i = 0; i < ${#b[@]}; i++)); do
        local av="${a[i]:-0}" bv="${b[i]:-0}"
        if ((av > bv)); then return 0; fi
        if ((av < bv)); then return 1; fi
    done
    return 0
}

preflight_checks() {
    # Check docker is installed
    if ! command -v docker &>/dev/null; then
        echo "Error: docker is not installed or not in PATH" >&2
        echo "Install Docker: https://docs.docker.com/get-docker/" >&2
        exit 1
    fi

    # Check docker daemon is running
    if ! docker info &>/dev/null; then
        echo "Error: Docker daemon is not running" >&2
        echo "Start Docker and try again." >&2
        exit 1
    fi

    # Check minimum docker version
    local docker_version
    docker_version="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "")"
    # Strip any suffix like -ce or +azure
    docker_version="${docker_version%%-*}"
    docker_version="${docker_version%%+*}"
    if [[ -n "$docker_version" ]] && ! version_gte "$docker_version" "$MIN_DOCKER_VERSION"; then
        echo "Error: Docker version $docker_version is too old (need >= $MIN_DOCKER_VERSION)" >&2
        exit 1
    fi

    # On Docker Desktop (macOS/Windows), warn if memory is low
    local total_mem
    total_mem="$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo "")"
    if [[ -n "$total_mem" ]] && [[ "$total_mem" =~ ^[0-9]+$ ]]; then
        # MemTotal is in bytes; warn if < 4GB
        local min_bytes=4294967296
        if ((total_mem < min_bytes)); then
            local mem_gb=$(awk "BEGIN {printf \"%.1f\", $total_mem / 1073741824}")
            echo "Warning: Docker has only ${mem_gb}GB memory available (4GB+ recommended)" >&2
            echo "Increase memory in Docker Desktop settings if builds fail." >&2
        fi
    fi
}

cleanup() {
    local name="$1"
    echo "Removing container: $name"
    docker rm -f "$name" 2>/dev/null || true
    echo "RUNABILLY_CLEANED=$name"
}

build_image() {
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
        echo "Building base image: $IMAGE_NAME"
        docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
    fi
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    if [[ "$1" == "--cleanup" ]]; then
        [[ $# -lt 2 ]] && usage
        cleanup "$2"
        return
    fi

    local keep=false
    if [[ "$1" == "--keep" ]]; then
        keep=true
        shift
        [[ $# -lt 1 ]] && usage
    fi

    local git_url="$1"

    preflight_checks

    # Extract repo name from URL
    local repo_name
    repo_name="$(basename "$git_url" .git)"

    # Generate short hash for uniqueness
    local hash
    hash="$(echo "$git_url" | portable_md5)"

    local container_name="runa-${repo_name}-${hash}"

    # Build image if needed
    build_image

    # Remove any existing container with the same name
    docker rm -f "$container_name" 2>/dev/null || true

    # Create and start the container
    echo "Creating container: $container_name"
    docker run -d \
        --name "$container_name" \
        --memory=4g \
        "$IMAGE_NAME" \
        sleep infinity >/dev/null

    # Clone the repo inside the container
    echo "Cloning $git_url into container..."
    docker exec "$container_name" \
        git clone "$git_url" /workspace/project

    echo ""
    echo "RUNABILLY_CONTAINER=$container_name"
    echo "RUNABILLY_WORKDIR=/workspace/project"

    if [[ "$keep" == true ]]; then
        echo ""
        echo "Container is running and ready for exploration."
        echo "To enter the container:"
        echo "  docker exec -it $container_name bash"
        echo ""
        echo "The project is cloned at /workspace/project inside the container."
        echo ""
        echo "When done, clean up with:"
        echo "  $0 --cleanup $container_name"
    fi
}

main "$@"
