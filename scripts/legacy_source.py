"""Materialize the immutable old-code migration fixture from Git, never user data."""
from contextlib import contextmanager
from pathlib import Path, PurePosixPath
import json, shutil, subprocess, tarfile, tempfile
from project_paths import ROOT, LEGACY_FIXTURE

@contextmanager
def materialized_legacy_fixture():
    pin = json.loads((ROOT/'tests/integration/legacy_source.json').read_text())
    actual = subprocess.run(['git','-C',str(ROOT),'rev-parse',pin['commit']+':'+pin['sourcePath']],check=True,capture_output=True,text=True).stdout.strip()
    if actual != pin['treeSHA']: raise RuntimeError('Pinned legacy source tree differs')
    with tempfile.TemporaryDirectory(prefix='together-legacy-source-') as folder:
        directory=Path(folder);archive=directory/'source.tar'
        subprocess.run(['git','-C',str(ROOT),'archive','--format=tar','--output',str(archive),pin['commit'],pin['sourcePath']],check=True,capture_output=True)
        with tarfile.open(archive) as tar:
            for member in tar.getmembers():
                name=PurePosixPath(member.name)
                if name.is_absolute() or '..' in name.parts or not (member.isfile() or member.isdir()):
                    raise RuntimeError('Unsafe entry in pinned source archive')
            tar.extractall(directory)
        harness=directory/'legacy-fixture';harness.mkdir()
        shutil.copytree(LEGACY_FIXTURE/'Sources',harness/'Sources')
        (harness/'Package.swift').write_text((LEGACY_FIXTURE/'Package.swift.template').read_text())
        yield harness
