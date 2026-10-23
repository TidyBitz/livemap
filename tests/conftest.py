"""Every test runs the helper package against a throwaway data folder and never touches the network:
`_http` is replaced with a fetcher that serves recorded fixtures (tests/fixtures/) or raises."""
import os
import pathlib
import shutil
import sys
import tempfile

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HELPER_DIR = ROOT / "livemap" / "contents" / "helper"
FIXTURES = pathlib.Path(__file__).resolve().parent / "fixtures"
sys.path.insert(0, str(HELPER_DIR))

# the package reads XDG_DATA_HOME when imported: point it at a scratch folder before the first import
_XDG = pathlib.Path(tempfile.mkdtemp(prefix="livemap-tests-"))
os.environ["XDG_DATA_HOME"] = str(_XDG)


@pytest.fixture(autouse=True)
def data_dir():
    """A clean data folder for every test."""
    d = _XDG / "livemap"
    shutil.rmtree(d, ignore_errors=True)
    d.mkdir(parents=True)
    yield d


@pytest.fixture
def no_network(monkeypatch):
    """Every HTTP call raises unless the test registered a response: serve(url_substring, text | bytes | Path)."""
    responses = {}

    def serve(part, body):
        responses[part] = body

    def fake_http(url, method="GET", timeout=6, limit=None, headers=None):
        for part, body in responses.items():
            if part in str(url):
                if isinstance(body, pathlib.Path):
                    body = body.read_bytes()
                if isinstance(body, str):
                    body = body.encode("utf-8")
                return 200, {}, body, 0.01
        raise OSError("no network in tests: %s" % url)

    import urllib.request
    for name, mod in list(sys.modules.items()):
        if name.startswith("livemap_helper") and hasattr(mod, "_http"):
            monkeypatch.setattr(mod, "_http", fake_http)

    def no_urlopen(*a, **k):
        raise OSError("no network in tests")
    monkeypatch.setattr(urllib.request, "urlopen", no_urlopen)
    return serve


def fixture(name):
    return (FIXTURES / name).read_text(encoding="utf-8")
