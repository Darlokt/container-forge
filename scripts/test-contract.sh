#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$repo_root/scripts/validate-contract.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

cp "$repo_root"/{.python-version,apt-build.txt,apt-runtime.txt,Dockerfile,pyproject.toml,uv.lock} "$fixture/"

run_in_fixture() {
  (cd "$fixture" && "$validator" "$@")
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    printf 'expected command to fail: %q ' "$@" >&2
    printf '\n' >&2
    exit 1
  fi
}

run_in_fixture environment
expect_failure run_in_fixture main
expect_failure run_in_fixture Feature/invalid

printf '3.12.1\n' > "$fixture/.python-version"
expect_failure run_in_fixture environment
printf '99.99\n' > "$fixture/.python-version"
expect_failure run_in_fixture environment
printf '3.12\n' > "$fixture/.python-version"

sed -i 's/^ARG PYTHON_VERSION=3\.12$/ARG PYTHON_VERSION=3.13/' "$fixture/Dockerfile"
expect_failure run_in_fixture environment
cp "$repo_root/Dockerfile" "$fixture/Dockerfile"

printf '%s\n' '--allow-unauthenticated' > "$fixture/apt-runtime.txt"
expect_failure run_in_fixture environment
cp "$repo_root/apt-runtime.txt" "$fixture/apt-runtime.txt"

sed -i 's/^dependencies = \[\]$/dependencies = ["requests"]/' "$fixture/pyproject.toml"
expect_failure run_in_fixture environment

printf 'contract validation tests passed\n'
