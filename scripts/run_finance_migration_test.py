#!/usr/bin/env python3
"""Upgrade an actual old-code store in private temporary storage; never open user data."""
from pathlib import Path
import os, subprocess, tempfile, sys
root=Path(__file__).resolve().parents[1]
cache=Path.home()/'.cache/Together/LegacyMigration-SPM'
cache.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='together-migration-') as directory:
    subprocess.run(['swift','run','--scratch-path',str(cache),'LegacyFixture',directory],cwd=root/'qa/migration/legacy_fixture',check=True)
    env=os.environ.copy();env['TOGETHER_LEGACY_FIXTURE']=directory
    command=['swift','test']
    if '--all-tests' not in sys.argv:command += ['--filter','FinanceMigrationTests']
    result=subprocess.run(command,cwd=root/'0.2.1',env=env)
    sys.exit(result.returncode)
