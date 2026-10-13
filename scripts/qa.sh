#!/usr/bin/env bash
set -euo pipefail
TASK_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_QA_ENV="$TASK_PROJECT_ROOT/.qa-runtime"
if [[ ! -x "$TASK_QA_ENV/bin/python" ]]; then
  TASK_QA_PYTHON="${TOGETHER_QA_PYTHON:-$(command -v python3.14 || command -v python3.13 || command -v python3)}"
  "$TASK_QA_PYTHON" -m venv "$TASK_QA_ENV"
fi
if ! "$TASK_QA_ENV/bin/python" -c 'from PIL import Image' >/dev/null 2>&1; then
  "$TASK_QA_ENV/bin/python" -m pip install --index-url https://pypi.org/simple -r "$TASK_PROJECT_ROOT/requirements-qa.txt"
fi
exec "$TASK_QA_ENV/bin/python" "$TASK_PROJECT_ROOT/scripts/run_qa.py" "$@"
