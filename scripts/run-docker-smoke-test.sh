#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 ]] || {
  printf 'usage: %s IMAGE PLATFORM\n' "$0" >&2
  exit 2
}

image="$1"
platform="$2"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp "$repo_root/scripts/container-smoke-test.sh" "$work/"
chmod 0777 "$work"

docker run --rm \
  --platform "$platform" \
  --user "$(id -u):$(id -g)" \
  --volume "$work:/work" \
  --workdir /work \
  "$image" \
  /bin/bash -ue /work/container-smoke-test.sh

[[ "$(<"$work/smoke-output.txt")" == nextflow-container-ok ]]
[[ "$(stat -c '%u' "$work/smoke-output.txt")" == "$(id -u)" ]]
