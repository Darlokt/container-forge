# container-forge

[![Publish environment](actions/workflows/publish.yml/badge.svg)](actions/workflows/publish.yml)
[![Python](https://img.shields.io/badge/Python-3.12%2B-blue?logo=python)](https://www.python.org/)
[![Package Manager](https://img.shields.io/badge/Package_Manager-uv-lightgrey)](https://github.com/astral-sh/uv)
[![Hooks](https://img.shields.io/badge/Hooks-prek-lightgrey)](https://github.com/j178/prek)
[![Nextflow compatible](https://img.shields.io/badge/Nextflow-compatible-0DC09D)](https://www.nextflow.io/)
[![Apptainer compatible](https://img.shields.io/badge/Apptainer-compatible-0B3D91)](https://apptainer.org/)

This repository publishes one locked Python environment per Git branch for use
by Nextflow processes. The `main` branch is a template and cannot be published.
Every other valid branch publishes to its own GitHub Container Registry package:

```text
ghcr.io/OWNER/REPOSITORY/BRANCH:latest
ghcr.io/OWNER/REPOSITORY/BRANCH:FULL_GIT_COMMIT_SHA
```

Use a commit tag or image digest in a released pipeline. The `latest` tag is
intended for interactive testing and moves whenever that environment is
published again.

## Table of contents

- [Environment branch contract](#environment-branch-contract)
- [Create or update an environment](#create-or-update-an-environment)
- [Publish manually](#publish-manually)
- [Use from Nextflow](#use-from-nextflow)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## Environment branch contract

Every environment branch must keep these files:

- `.python-version`: exactly one supported Python `major.minor` value; the
  template accepts CPython 3.10 through 3.14.
- `pyproject.toml`: runtime Python dependencies and `[tool.uv] package = false`.
- `uv.lock`: the committed uv lockfile.
- `apt-runtime.txt`: optional Debian runtime packages, one per line.
- `apt-build.txt`: optional build-only Debian packages, one per line.
- The shared Dockerfile, workflow, and scripts inherited from `main`.

Package entries may be unversioned (`libgomp1`) or pinned
(`libgomp1=12.2.0-14+deb12u1`). Blank lines and `#` comments are accepted.
Build packages are omitted from the final image. Python development dependency
groups are also omitted. The template includes `prek` in the development group
for local commit-time checks; the container smoke test explicitly verifies that
its executable is absent from the final image.

Publishable branch names must be lowercase, must not contain `/`, and must
match:

```text
^[a-z0-9][a-z0-9._-]*$
```

This restriction makes the branch-to-GHCR-package mapping unambiguous.

## Create or update an environment

Create a branch from the latest `main` template:

```bash
git switch main
git pull --ff-only
git switch -c pandas
```

Choose Python and add dependencies with uv:

```bash
printf '3.12\n' > .python-version
uv python pin 3.12
uv add pandas pyarrow
```

If a Python dependency needs system libraries or compilation, add Debian
packages to `apt-runtime.txt` and `apt-build.txt` respectively. Then validate
the branch contract:

```bash
uv lock
./scripts/validate-contract.sh pandas
./scripts/test-contract.sh
```

Install the development environment and Git hook once per clone:

```bash
uv sync
uv run prek install
```

Before committing, the hook pinned in `.pre-commit-config.yaml` runs uv 0.11.28
to refresh `uv.lock`, followed by repository contract validation. If the lock
changes, stage it and commit again. Run the same checks manually at any time:

```bash
uv run prek run --all-files
```

Commit all environment and shared files, including `uv.lock`. Changes to the
shared Dockerfile or workflow are made on `main` and then merged into each
environment branch. This ensures the branch commit records every build input.

## Publish manually

1. Open the repository's **Actions** tab and select **Build and publish environment**.
2. Choose **Run workflow**, then select the environment branch, not `main`.
3. Leave `include_arm64` disabled for an amd64-only image, or enable it to test
   both architectures and publish a multi-platform manifest.
4. Run the workflow.

The workflow validates the lock and branch contract, rejects an existing
commit-SHA tag, tests each requested architecture, publishes `latest` and the
full commit SHA, creates build provenance, and pulls the published amd64 digest
through Apptainer for a final mounted-script smoke test.

GitHub creates each new GHCR package as private. After the first successful
publish, open the package settings and change its visibility to **Public**.
Repeat this once for every new environment branch/package. Public images can be
pulled anonymously by HPC workers. The CI smoke test authenticates with its
short-lived `GITHUB_TOKEN`, so it also works during the initial private state.

## Use from Nextflow

The image contains the environment, not pipeline scripts. Nextflow stages the
Python file into its task directory and invokes it with the environment's
`python` on `PATH`:

```nextflow
process analyse {
    container 'ghcr.io/OWNER/REPOSITORY/pandas:FULL_GIT_COMMIT_SHA'

    input:
    path python_script
    path input_file

    output:
    path 'result.json'

    script:
    """
    python ${python_script} ${input_file} result.json
    """
}
```

For a portable configuration, use the normal GHCR name without a `docker://`
prefix:

```groovy
process.container = 'ghcr.io/OWNER/REPOSITORY/pandas:FULL_GIT_COMMIT_SHA'

profiles {
    docker {
        docker.enabled = true
    }
    apptainer {
        apptainer.enabled = true
        apptainer.autoMounts = true
    }
}
```

Nextflow adds `docker://` when Apptainer needs to pull from GHCR. On clusters,
set `NXF_APPTAINER_CACHEDIR` to a shared, writable filesystem visible to the
launch host and compute nodes.

For a direct Docker check, mount a staged script and override the default Bash
command:

```bash
docker run --rm \
  -v "$PWD:/work" -w /work \
  ghcr.io/OWNER/REPOSITORY/pandas:FULL_GIT_COMMIT_SHA \
  /bin/bash -ue /work/my-script.sh
```

## Troubleshooting

- **`uv.lock` is out of date:** run `uv lock`, validate, and commit the result.
- **Python mismatch:** keep `.python-version`, `project.requires-python`, and
  the lockfile compatible. The build will not download a substitute Python.
- **An ARM build fails:** a dependency may lack an arm64 wheel or an apt package
  may be architecture-specific. Add the required build packages or publish
  amd64 only.
- **An apt package cannot be found:** package names and versions must exist in
  Debian Trixie for every selected architecture. Avoid unnecessary exact apt
  pins because Debian security updates replace older versions.
- **A private Python index is required:** this template intentionally supports
  public indexes only. Add BuildKit secret handling before using credentials;
  never commit index tokens.
- **GHCR pulls fail on the cluster:** make the package public or configure
  Apptainer registry credentials. Confirm the shared cache path is writable and
  supports atomic rename.
- **A commit tag already exists:** immutable tags are never overwritten. Commit
  the intended change and publish the new SHA.

## References

- [Using uv in Docker](https://docs.astral.sh/uv/guides/integration/docker/)
- [prek](https://prek.j178.dev/)
- [Nextflow containers and Apptainer](https://docs.seqera.io/nextflow/container)
- [Manually running GitHub Actions workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
- [Publishing Docker images with GitHub Actions](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Installing Apptainer](https://apptainer.org/docs/admin/main/installation.html)
