#!/usr/bin/env python3
"""Restore pinned old source privately, create an old store, test compatible upgrade."""
from pathlib import Path
import os, subprocess, tempfile, sys
from project_paths import ROOT, CORE
from legacy_source import materialized_legacy_fixture
cache=ROOT/'qa/results/tool-caches/legacy-migration-swift'
cache.mkdir(parents=True,exist_ok=True)
parent=Path(os.environ.get('TOGETHER_MIGRATION_TEMP_PARENT',str(ROOT/'qa/results/migration-runtime'))).absolute()
allowed=(ROOT/'qa/results').resolve()
if parent.resolve()!=parent or not (parent==allowed or allowed in parent.parents):
    raise RuntimeError('Migration temporary parent must be a canonical directory inside project qa/results')
parent.mkdir(mode=0o700,parents=True,exist_ok=True)
if parent.is_symlink() or parent.stat().st_uid!=os.getuid():
    raise RuntimeError('Migration temporary parent must be owned by the current user without symlinks')
os.environ['TOGETHER_MIGRATION_TEMP_PARENT']=str(parent)
os.environ['TOGETHER_MIGRATION_PROJECT_ROOT']=str(ROOT)
os.environ['TMPDIR']=str(parent)
tempfile.tempdir=str(parent)
with tempfile.TemporaryDirectory(prefix='together-migration-',dir=parent) as directory:
    with materialized_legacy_fixture() as legacy:
        subprocess.run(['swift','run','--scratch-path',str(cache),'LegacyFixture',directory],cwd=legacy,check=True)
    env=os.environ.copy();env['TOGETHER_LEGACY_FIXTURE']=directory
    command=['swift','test']
    if '--all-tests' not in sys.argv:command += ['--filter','FinanceMigrationTests']
    result=subprocess.run(command,cwd=CORE,env=env)
    sys.exit(result.returncode)
