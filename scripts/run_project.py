#!/usr/bin/env python3
"""Resolve the selected version without constructing shell commands."""
from pathlib import Path
import json, subprocess, sys

from project_paths import ROOT as root, APP as project, CORE
if root not in project.parents:
    raise SystemExit('projectDirectory must be inside Together')
commands = {'build': ['./script/build_and_run.sh', '--build-only'], 'test': ['swift', 'test'],
            'package': [sys.executable, 'script/package_app.py']}
if len(sys.argv) != 2 or sys.argv[1] not in commands:
    raise SystemExit('usage: run_project.py build|test|package')
raise SystemExit(subprocess.run(commands[sys.argv[1]], cwd=CORE if sys.argv[1] == "test" else project).returncode)
