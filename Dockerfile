FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    git-lfs \
    curl \
    wget \
    build-essential \
    ca-certificates \
    sudo \
    less \
    file \
    && rm -rf /var/lib/apt/lists/*

# git-lfs is installed but not enabled system-wide on purpose: clones leave LFS
# pointer files in place by default, and Claude opts in per-repo with
# `git lfs install --local && git lfs pull` only when LFS-tracked files are
# actually needed for the build or tests. This avoids surprise multi-GB pulls
# on data-heavy bioinformatics repos.

WORKDIR /workspace

CMD ["sleep", "infinity"]
