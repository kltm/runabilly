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

    # Warn if the Docker root directory is low on disk. Bioinformatics repos
    # with Git LFS data, conda environments, or Bioconductor builds can blow
    # through tens of GB; we want the user to know before that happens.
    # On macOS/Windows the Docker root lives inside a VM so this check is
    # best-effort and silently skipped if the path isn't on the host.
    local docker_root
    docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "")"
    if [[ -n "$docker_root" ]] && [[ -d "$docker_root" ]]; then
        local avail_kb
        avail_kb="$(df -Pk "$docker_root" 2>/dev/null | awk 'NR==2 {print $4}')"
        if [[ -n "$avail_kb" ]] && [[ "$avail_kb" =~ ^[0-9]+$ ]]; then
            local avail_gb
            avail_gb=$(awk "BEGIN {printf \"%.1f\", $avail_kb / 1048576}")
            # 20 GB soft floor — enough for most builds; LFS-heavy repos may need more
            if ((avail_kb < 20971520)); then
                echo "Warning: only ${avail_gb}GB free at Docker root ($docker_root)" >&2
                echo "  Builds with large dependencies may fail. If the target repo uses Git LFS," >&2
                echo "  pulling its data could exhaust this space. Consider freeing up disk:" >&2
                echo "    docker system prune -af --volumes" >&2
            fi
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

    # Clone the repo inside the container.
    # GIT_LFS_SKIP_SMUDGE=1 leaves any LFS-tracked files as pointer stubs so a
    # data-heavy repo doesn't silently pull tens of GB during setup. The skill
    # decides per-repo whether to materialise them with `git lfs pull`.
    echo "Cloning $git_url into container..."
    docker exec -e GIT_LFS_SKIP_SMUDGE=1 "$container_name" \
        git clone "$git_url" /workspace/project

    # If the repo uses Git LFS, surface that to the caller so they (and the
    # skill) know there are pointer files in place.
    if docker exec "$container_name" \
        bash -c 'grep -lq "filter=lfs" /workspace/project/.gitattributes 2>/dev/null'; then
        echo "Note: this repo uses Git LFS. Pointer files left in place." >&2
        echo "  To materialise: docker exec $container_name bash -c 'cd /workspace/project && git lfs install --local && git lfs pull'" >&2
    fi

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
