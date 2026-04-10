---
name: runabilly
description: Explore, build, and run an open source project in a disposable Docker container
disable-model-invocation: true
---

Runabilly: explore, build, and run an open source project in a disposable Docker container.

Input: $ARGUMENTS (a git URL, optionally preceded by `--keep`)

Parse the arguments: if `--keep` is present, set KEEP_CONTAINER=true, otherwise KEEP_CONTAINER=false. The git URL is always the last argument.

**Timeout:** The entire evaluation (setup through build) must complete within 1 hour. Record the start time at the beginning. Before each build attempt, check elapsed time. If 1 hour has passed, stop immediately, clean up the container, and report the build result as FAILURE with "Timed out after 1 hour" in issues encountered. A timeout is always a FAILURE — even if the build might eventually succeed given more time, exceeding the timeout means the project cannot be built within the constraints of a disposable container evaluation.

Follow these steps:

## 1. Setup

Run `./runabilly.sh $ARGUMENTS` and parse the output for `RUNABILLY_CONTAINER=<name>` and `RUNABILLY_WORKDIR=<workdir>`. Save both values — use them in all subsequent `docker exec` commands.

If setup fails, report the error and stop.

## 2. Explore

Run these inside the container to understand the project:

```
docker exec <container> bash -c 'ls -la /workspace/project/'
docker exec <container> bash -c 'cat /workspace/project/README.md 2>/dev/null || echo "No README found"'
```

Then run the build-system probe. This is a deliberately broad scan, not a closed list — anything not detected here can still be built (see "Improvisation policy" below):

```
docker exec <container> bash -c 'cd /workspace/project && \
echo "=== Build system markers ===" && \
for f in \
    Makefile GNUmakefile CMakeLists.txt configure configure.ac meson.build SConstruct \
    BUILD BUILD.bazel WORKSPACE MODULE.bazel build.zig \
    setup.py setup.cfg pyproject.toml requirements.txt Pipfile Pipfile.lock poetry.lock tox.ini \
    environment.yml environment.yaml conda.yml conda.yaml pixi.toml \
    package.json yarn.lock pnpm-lock.yaml deno.json \
    Cargo.toml go.mod pom.xml build.gradle build.gradle.kts build.sbt settings.gradle \
    mix.exs rebar.config stack.yaml dune-project \
    Project.toml Manifest.toml JuliaProject.toml \
    DESCRIPTION NAMESPACE renv.lock \
    Snakefile nextflow.config main.nf \
    Gemfile composer.json cpanfile Makefile.PL \
    Dockerfile docker-compose.yml Containerfile Singularity Singularity.def; do
  [ -e "$f" ] && echo "FOUND: $f"
done && \
echo "=== Workflow / domain files ===" && \
find . -maxdepth 3 \( -name "*.smk" -o -name "*.nf" -o -name "*.cwl" -o -name "*.wdl" -o -name "*.Rproj" -o -name "*.cabal" -o -name "*.rockspec" \) 2>/dev/null | head -20 && \
echo "=== Git LFS ===" && \
( grep -lq "filter=lfs" .gitattributes 2>/dev/null && echo "REPO USES GIT LFS (pointer files only; run git lfs install --local && git lfs pull to materialise)" || echo "No LFS markers" ) && \
echo "=== CI configs (often reveal canonical build/test commands) ===" && \
( ls -d .github/workflows .gitlab-ci.yml .travis.yml .circleci azure-pipelines.yml 2>/dev/null || echo "No CI configs found" )'
```

Identify the build system and language from the files present. If multiple are present (e.g., a Python project that wraps a Snakemake workflow), pick the one that matches the project's stated purpose in its README. If nothing recognisable shows up, fall back to reading the README and any `INSTALL`, `BUILDING`, `CONTRIBUTING` files.

## 3. Install

Based on what you discovered, install the required toolchain inside the container. The base image only has git, curl, build-essential, and git-lfs — every language/runtime must be added per project. The hints below are starting points, not a closed list. If a project needs something not listed, install it (see "Improvisation policy" below).

All installs run via: `docker exec <container> bash -c '...'`

**Compiled / systems:**
- **C/C++ (autotools):** `apt-get update && apt-get install -y autoconf automake libtool pkg-config`
- **C/C++ (cmake):** `apt-get update && apt-get install -y cmake`
- **C/C++ (meson):** `apt-get update && apt-get install -y meson ninja-build`
- **Rust:** `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && . "$HOME/.cargo/env"`
- **Go:** `apt-get update && apt-get install -y golang-go`
- **Fortran:** `apt-get update && apt-get install -y gfortran`
- **Zig:** download from `https://ziglang.org/download/` (no apt package)

**JVM:**
- **Java (Maven):** `apt-get update && apt-get install -y default-jdk maven`
- **Java (Gradle):** `apt-get update && apt-get install -y default-jdk gradle` (or use the project's `./gradlew`)
- **Scala (sbt):** `apt-get update && apt-get install -y default-jdk` then install sbt from `https://www.scala-sbt.org/`
- **Bazel:** install from `https://bazel.build/install/ubuntu` (or use `bazelisk`)

**Interpreted / scripting:**
- **Python:** `apt-get update && apt-get install -y python3 python3-pip python3-venv python3-dev`
  - Use a venv (`python3 -m venv .venv && . .venv/bin/activate`) to avoid PEP 668 "externally-managed-environment" errors on Ubuntu 24.04.
- **Node.js:** `curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && apt-get install -y nodejs`
- **Ruby:** `apt-get update && apt-get install -y ruby-full`
- **Perl:** Perl is preinstalled; add `apt-get install -y cpanminus` for CPAN modules.
- **PHP:** `apt-get update && apt-get install -y php php-cli composer`

**Scientific / data:**
- **R:** `apt-get update && apt-get install -y r-base r-base-dev` then `R -e 'install.packages(c(...), repos="https://cloud.r-project.org")'` or `R CMD INSTALL .` for the package itself. For Bioconductor: `R -e 'install.packages("BiocManager"); BiocManager::install(c(...))'`. For renv-managed projects: `R -e 'renv::restore()'`.
- **Julia:** `curl -fsSL https://install.julialang.org | sh -s -- --yes` then `~/.juliaup/bin/julia --project -e 'using Pkg; Pkg.instantiate()'`
- **Conda / Mamba (miniforge):** `curl -fsSL -o /tmp/mf.sh https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh && bash /tmp/mf.sh -b -p /opt/conda && export PATH=/opt/conda/bin:$PATH && conda env create -f environment.yml`

**Bioinformatics workflow engines:**
- **Snakemake:** install Python first, then `pip install snakemake` (or `conda install -c bioconda snakemake`). Run with `snakemake --cores all` or whatever the README specifies.
- **Nextflow:** `apt-get update && apt-get install -y default-jre && curl -fsSL https://get.nextflow.io | bash && mv nextflow /usr/local/bin/`. Run with `nextflow run main.nf`.
- **CWL (cwltool):** install Python first, then `pip install cwltool`. Run with `cwltool workflow.cwl inputs.yml`.
- **WDL (miniwdl):** install Python first, then `pip install miniwdl`. Run with `miniwdl run workflow.wdl`. Cromwell is an alternative if the project specifies it.
- **Galaxy tools:** typically need `planemo` (`pip install planemo`).

**Other ecosystems:**
- **Haskell (Stack):** `curl -sSL https://get.haskellstack.org/ | sh`
- **Haskell (Cabal):** `apt-get install -y ghc cabal-install`
- **OCaml (Dune):** `apt-get install -y opam && opam init -y && opam install dune`
- **Elixir/Erlang (Mix):** `apt-get install -y elixir`

**Containers as build artefacts:** if the project's canonical entry point is a `Dockerfile`, the build *is* `docker build`. Runabilly cannot run Docker-in-Docker — report this as a WARNING and explain the hurdle (see step 6).

Install any additional system dependencies mentioned in the README, INSTALL, or CI configs (`apt-get install -y <pkgs>`).

## 4. Build

Attempt to build the project following the discovered instructions. Common patterns:

- **autotools:** `autoreconf -i && ./configure && make`
- **cmake:** `mkdir build && cd build && cmake .. && make`
- **make:** `make`
- **python (PEP 517):** `python3 -m venv .venv && . .venv/bin/activate && pip install -e .` (or `pip install .`)
- **python (legacy):** `python setup.py build`
- **npm:** `npm install && npm run build` (or just `npm install` if there's no build script)
- **cargo:** `cargo build --release`
- **go:** `go build ./...`
- **maven:** `mvn -B package`
- **gradle:** `./gradlew build` (prefer the wrapper) or `gradle build`
- **R package:** `R CMD INSTALL .` (install BiocManager/CRAN deps from DESCRIPTION first)
- **Julia:** `julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.build()'`
- **Snakemake:** `snakemake --cores all -n` (dry-run first to validate the DAG, then a real run if a small example exists)
- **Nextflow:** `nextflow run main.nf -profile test` if a `test` profile exists, otherwise `nextflow run main.nf` against the smallest example inputs in the repo
- **CWL:** `cwltool workflow.cwl examples/inputs.yml` (use any provided example inputs)
- **WDL:** `miniwdl run workflow.wdl` with example inputs

Run the build commands inside the container:
```
docker exec <container> bash -c 'cd /workspace/project && <build-commands>'
```

If the build fails, read the error output, try to diagnose and fix (install missing deps, adjust commands), and retry. Make up to **3 build attempts** total. Each retry must be a real fix in response to the error — do not repeat the same command hoping for a different result.

## Improvisation policy ("playing jazz")

The detection list and install hints above cover common cases, but real-world projects deviate. You have **explicit permission to improvise** when the standard path doesn't work or doesn't apply:

- If the build-system probe finds nothing, read the README, `INSTALL`, `BUILDING`, `CONTRIBUTING`, and any `docs/` files, and infer tooling from imports, shebang lines, CI configs (`.github/workflows/`, `.gitlab-ci.yml`, `.travis.yml`, `tox.ini`, `noxfile.py`), or example commands.
- If a project uses a domain-specific or in-house build system not listed in step 3, install whatever it needs and try.
- If the documented build path fails, try reasonable alternates: a different toolchain version, an obvious flag (`--with-system-foo`, `-DCMAKE_BUILD_TYPE=Release`), an alternate target (`make all` vs `make`), a workaround mentioned in an open issue, or building a sub-component instead of the whole tree.
- If a dependency is unavailable in apt, fall back to language-native package managers (pip, cargo, gem, cpan, R `install.packages`, conda) or build from source.
- It's fine to read source files, scan imports, run small probes (`python3 -c "import x"`, `ldd binary`, `pkg-config --list-all`, `apt-cache search`), or check git tags/releases for a known-good commit if HEAD is broken.
- For Git LFS repos: only run `git lfs install --local && git lfs pull` if the LFS-tracked files are actually needed for the build or tests. Many repos LFS-track sample data that the build doesn't require — skip the pull and save the disk hit.

**What stays fixed (do not improvise around these):**

- Everything runs inside the container via `docker exec`. Never install or modify anything on the host.
- **3 build attempts max** before reporting FAILURE. Each attempt must include a substantive fix.
- **1-hour wall-clock timeout** for the entire evaluation (setup → report). When in doubt, check elapsed time before starting another attempt.
- **Do not disable safety mechanisms to fake a green status.** Skipping failing tests with `-k 'not broken'`, passing `--ignore-errors`, deleting failing test files, or stubbing out assertions all defeat the purpose of the report. If you can't make a real test pass, that's a FAILURE — report it honestly.
- No destructive actions outside the container. No `--no-verify` or hook bypasses.

## 5. Test

After a successful build, you **must** run the project's tests if any test infrastructure exists. The reviewer relies on test results to gauge whether a project actually works, not just whether it compiles. Look for:

- `tests/`, `test/`, `t/`, `spec/`, `__tests__/` directories
- Pytest/unittest in Python (`pytest`, `python -m unittest discover`); a `tox.ini` or `noxfile.py` is also a strong signal
- `cargo test` for Rust, `go test ./...` for Go, `npm test` / `npm run test` for Node, `mvn test` for Maven, `./gradlew test` for Gradle, `make check` or `make test` for autotools/make
- `R CMD check .` or `devtools::test()` for R packages, `testthat` directories
- `Pkg.test()` for Julia
- `snakemake --cores all -n` (DAG dry-run) and any `tests/` workflow for Snakemake
- `nextflow run main.nf -profile test` for Nextflow
- `cwltool --validate workflow.cwl` and example runs for CWL
- The project's CI config (`.github/workflows/*.yml`) is usually the canonical answer — if a CI job runs `pytest -xvs tests/`, do that.

Run the discovered test command inside the container:

```
docker exec <container> bash -c 'cd /workspace/project && <test-commands>'
```

**Test outcome rules:**

- Tests run and pass → **SUCCESS**.
- No test infrastructure exists at all → note "No tests present" and SUCCESS based on the build alone.
- Tests run but fail → **FAILURE**, even if the build itself worked. Try one fix attempt within the 3-attempt budget if the failure looks fixable (missing test dep, etc.); otherwise report honestly.
- Tests cannot run due to an unavoidable environmental hurdle (needs an external database, GPU, paid API key, network service, Docker-in-Docker) → **WARNING**, with the hurdle named explicitly in "Issues encountered". WARNING means "the code looks healthy but our environment can't validate it," not "we gave up early."
- Do not narrow the test selection just to get green output. If the project's CI runs the full suite, run the full suite.

## 6. Report

Output a structured summary:

```
## Runabilly Report

- **Project:** <name> (<url>)
- **Build system:** <detected build system>
- **Language:** <primary language>
- **Dependencies installed:** <list>
- **Build result:** SUCCESS / WARNING / FAILURE / UNDEFINED
  - SUCCESS: build completes AND the project's tests run and pass (or no test infrastructure is present)
  - WARNING: build completes but full test validation is blocked by an unavoidable environmental hurdle (e.g. Docker-in-Docker, large external databases, requires paid API keys, GPU-only). The code looks healthy; the environment can't validate it. Name the specific hurdle in "Issues encountered".
  - FAILURE: build fails after retries, OR tests run but fail, OR the 1-hour timeout is exceeded
  - UNDEFINED: URL isn't a buildable repo (e.g. Kaggle homepage, documentation site, dataset collection)
- **Tests:** <command run, pass/fail counts, or "No tests present">
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

## 7. Cleanup

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
