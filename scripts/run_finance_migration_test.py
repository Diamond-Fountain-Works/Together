#!/usr/bin/env python3
"""Restore pinned old source privately, create an old store, test compatible upgrade."""
from pathlib import Path
import os, subprocess, tempfile, sys
from project_paths import ROOT, CORE
from legacy_source import materialized_legacy_fixture
cache=Path.home()/'.cache/Together/LegacyMigration-SPM'
cache.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='together-migration-') as directory:
    with materialized_legacy_fixture() as legacy:
        subprocess.run(['swift','run','--scratch-path',str(cache),'LegacyFixture',directory],cwd=legacy,check=True)
    env=os.environ.copy();env['TOGETHER_LEGACY_FIXTURE']=directory
    command=['swift','test']
    if '--all-tests' not in sys.argv:command += ['--filter','FinanceMigrationTests']
    result=subprocess.run(command,cwd=CORE,env=env)
    sys.exit(result.returncode)
