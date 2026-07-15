#!/usr/bin/env bash
set -euo pipefail

branch="${1:-}"
required_files=(
  .python-version
  apt-build.txt
  apt-runtime.txt
  Dockerfile
  pyproject.toml
  uv.lock
)

fail() {
  printf 'contract validation failed: %s\n' "$*" >&2
  exit 1
}

for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || fail "missing required file: $file"
done

if [[ -n "$branch" ]]; then
  [[ "$branch" != main ]] || fail "main is the non-publishable template branch"
  [[ "$branch" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || \
    fail "branch must match ^[a-z0-9][a-z0-9._-]*$ (lowercase, no slash)"
fi

python_version="$(<.python-version)"
[[ "$python_version" =~ ^[0-9]+\.[0-9]+$ ]] || \
  fail ".python-version must contain exactly one major.minor value"
case "$python_version" in
  3.10 | 3.11 | 3.12 | 3.13 | 3.14) ;;
  *) fail "unsupported Python $python_version; supported versions are 3.10 through 3.14" ;;
esac

mapfile -t docker_python_versions < <(
  sed -nE \
    's/^[[:space:]]*ARG[[:space:]]+PYTHON_VERSION=([0-9]+\.[0-9]+)[[:space:]]*(#.*)?$/\1/p' \
    Dockerfile
)
[[ "${#docker_python_versions[@]}" -eq 1 ]] || \
  fail "Dockerfile must declare exactly one ARG PYTHON_VERSION=major.minor default"
[[ "${docker_python_versions[0]}" == "$python_version" ]] || \
  fail "Dockerfile ARG PYTHON_VERSION=${docker_python_versions[0]} does not match .python-version ($python_version)"

grep -Eq '^[[:space:]]*package[[:space:]]*=[[:space:]]*false([[:space:]]*(#.*)?)?$' pyproject.toml || \
  fail "pyproject.toml must declare package = false"

validate_apt_file() {
  local file="$1"
  local line trimmed line_number=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    trimmed="${line%%#*}"
    trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -z "$trimmed" ]] && continue
    [[ "$trimmed" =~ ^[a-z0-9][a-z0-9+.-]*(=[A-Za-z0-9.+:~_-]+)?$ ]] || \
      fail "$file:$line_number is not a package name or name=version entry"
  done < "$file"
}

validate_apt_file apt-build.txt
validate_apt_file apt-runtime.txt

command -v uv >/dev/null 2>&1 || fail "uv is required for lockfile validation"
UV_PYTHON_DOWNLOADS=0 uv lock --check >/dev/null || \
  fail "uv.lock is missing or out of date; run uv lock and commit it"

printf 'contract validation passed%s (Python %s)\n' \
  "${branch:+ for branch $branch}" "$python_version"
