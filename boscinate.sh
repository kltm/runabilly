#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="boscinator-base"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $0 <git-url>"
    echo "       $0 --cleanup <container-name>"
    exit 1
}

cleanup() {
    local name="$1"
    echo "Removing container: $name"
    docker rm -f "$name" 2>/dev/null || true
    echo "BOSCINATOR_CLEANED=$name"
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

    local git_url="$1"

    # Extract repo name from URL
    local repo_name
    repo_name="$(basename "$git_url" .git)"

    # Generate short hash for uniqueness
    local hash
    hash="$(echo "$git_url" | md5sum | cut -c1-8)"

    local container_name="bosc-${repo_name}-${hash}"

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
    echo "BOSCINATOR_CONTAINER=$container_name"
    echo "BOSCINATOR_WORKDIR=/workspace/project"
}

main "$@"
