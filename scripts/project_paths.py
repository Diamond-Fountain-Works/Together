"""Authoritative source locations; never depends on a version-named folder."""
from pathlib import Path
import json
ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / 'qa/project.json').read_text())
def location(key):
    path = (ROOT / CONFIG[key]).resolve()
    if ROOT not in path.parents:
        raise ValueError(key + ' must stay inside the repository')
    return path
APP = location('projectDirectory')
CORE = location('coreDirectory')
RELAY = location('relayDirectory')
LEGACY_FIXTURE = location('legacyFixtureDirectory')
