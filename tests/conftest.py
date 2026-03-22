import sys
from pathlib import Path

# Make hooks/slipstream package importable in tests
sys.path.insert(0, str(Path(__file__).parent.parent / "hooks"))

import pytest


HOOKS_DIR = Path(__file__).parent.parent / "hooks"
FIXTURES_DIR = Path(__file__).parent / "fixtures"


@pytest.fixture
def tmp_home(monkeypatch, tmp_path):
    """Redirect HOME to an isolated temp dir so tests never touch ~/.slipstream."""
    monkeypatch.setenv("HOME", str(tmp_path))
    (tmp_path / ".slipstream").mkdir()
    (tmp_path / ".claude" / "projects").mkdir(parents=True)
    # Reload DATA_DIR in lib so it picks up the patched HOME
    import slipstream.lib as lib
    lib.DATA_DIR = tmp_path / ".slipstream"
    return tmp_path
