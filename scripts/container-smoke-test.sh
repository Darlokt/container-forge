#!/usr/bin/env bash
set -euo pipefail

[[ "${VIRTUAL_ENV:-}" == /opt/venv ]]
[[ "$(command -v python)" == /opt/venv/bin/python ]]
command -v ps >/dev/null
! command -v prek >/dev/null

python - <<'PY'
from pathlib import Path
import sys

assert sys.prefix == "/opt/venv", sys.prefix
Path("smoke-output.txt").write_text("nextflow-container-ok\n", encoding="utf-8")
print("nextflow-container-ok")
PY

[[ "$(<smoke-output.txt)" == nextflow-container-ok ]]
