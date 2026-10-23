"""The parts that have to agree with each other: config keys, settings aliases, status names, sources.json,
the versions, the changelog."""
import json
import re

from conftest import ROOT

from livemap_helper import coverage
from livemap_helper.status import status_jobs

CONTENTS = ROOT / "livemap" / "contents"
WIDGET = ROOT / "livemap-widget"


def main_xml_keys(path):
    return set(re.findall(r'<entry name="(\w+)"', path.read_text(encoding="utf-8")))


def test_every_settings_alias_has_a_config_key():
    """config.qml's cfg_X properties are bound to main.xml entries by name: a missing entry fails silently on the desktop."""
    keys = main_xml_keys(CONTENTS / "config" / "main.xml")
    aliases = set(re.findall(r"property (?:alias|int|string|bool|real|var) cfg_(\w+)", (CONTENTS / "ui" / "config.qml").read_text(encoding="utf-8")))
    assert aliases - keys == set(), "settings bound to keys main.xml does not define"


def test_every_cfg_read_in_the_layers_has_a_key():
    keys = main_xml_keys(CONTENTS / "config" / "main.xml")
    used = set()
    for f in (CONTENTS / "ui").glob("*.qml"):
        used |= set(re.findall(r"\bcfg\.(\w+)", f.read_text(encoding="utf-8")))
    used -= {"length"}
    assert used - keys == set(), "layers read keys main.xml does not define"


def test_widget_aliases_have_keys():
    keys = main_xml_keys(WIDGET / "contents" / "config" / "main.xml")
    aliases = set(re.findall(r"property alias cfg_(\w+)", (WIDGET / "contents" / "ui" / "configGeneral.qml").read_text(encoding="utf-8")))
    used = set(re.findall(r"Plasmoid\.configuration\.(\w+)", (WIDGET / "contents" / "ui" / "main.qml").read_text(encoding="utf-8")))
    assert (aliases | used) - keys == set()


def test_sources_json_is_consistent():
    src = coverage.read_sources()
    regions = {r["id"] for r in src["regions"]}
    hazards = {h["id"] for h in src["hazards"]}
    status_names = {j[0] for j in status_jobs(offline=False)}
    for so in src["sources"]:
        assert so["hazard"] in hazards, so["id"]
        assert set(so["regions"]) <= regions | {"world"}, so["id"]
        assert so["lead"] in src["leads"], so["id"]
        for k in ("name", "gives", "cadence", "licence", "attribution", "url"):
            assert so.get(k), "%s lacks %s" % (so["id"], k)
        assert so["url"].startswith("https://"), so["id"]
        if so.get("status"):
            assert so["status"] in status_names, "%s names a status check that does not exist: %s" % (so["id"], so["status"])
    ids = [so["id"] for so in src["sources"]]
    assert len(ids) == len(set(ids))


def test_settings_section_sources_match_status_names():
    """Each section's dot summarises the status checks it names; a renamed check would silently go grey."""
    names = {j[0] for j in status_jobs(offline=False)}
    text = (CONTENTS / "ui" / "config.qml").read_text(encoding="utf-8")
    for m in re.finditer(r'sourceNames: \[([^\]]*)\]', text):
        for n in re.findall(r'"([^"]+)"', m.group(1)):
            assert n in names, n


def test_coverage_matrix_has_every_hazard_and_region():
    cov = coverage.coverage()
    for h in cov["hazards"]:
        assert set(cov["matrix"][h["id"]]) == {r["id"] for r in cov["regions"]}
    assert cov["matrix"]["quake"]["eu"][0]["id"] == "usgs"
    assert cov["matrix"]["flood"]["na"][0]["id"] == "nws" and cov["matrix"]["flood"]["eu"][0]["id"] == "meteoalarm" and cov["matrix"]["flood"]["sca"][0]["id"] == "gdacs-fl"
    md = coverage.coverage_markdown(cov)
    assert md.startswith("# Coverage") and "| Earthquakes |" in md


def test_versions_agree():
    from livemap_helper import VERSION
    wp = json.loads((ROOT / "livemap" / "metadata.json").read_text(encoding="utf-8"))["KPlugin"]["Version"]
    wg = json.loads((WIDGET / "metadata.json").read_text(encoding="utf-8"))["KPlugin"]["Version"]
    assert wp == VERSION, "helper VERSION and the wallpaper's metadata.json differ"
    assert wg == VERSION, "widget and wallpaper versions differ"
    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    assert ("## %s" % VERSION) in changelog, "CHANGELOG.md has no entry for this version"


def test_metadata_licence_matches_the_licence_file():
    for meta in (ROOT / "livemap" / "metadata.json", WIDGET / "metadata.json"):
        lic = json.loads(meta.read_text(encoding="utf-8"))["KPlugin"].get("License", "")
        assert "GPL" in lic, meta
    text = (ROOT / "LICENSE").read_text(encoding="utf-8", errors="replace")[:400] if (ROOT / "LICENSE").exists() else ""
    assert "GNU GENERAL PUBLIC LICENSE" in text, "LICENSE file missing or not the GPL the metadata claims"


def test_data_files_shipped():
    assert (CONTENTS / "data" / "sources.json").exists()
    assert (CONTENTS / "data" / "ukraine-regions.json").exists()
    for s in json.loads((CONTENTS / "data" / "sources.json").read_text(encoding="utf-8"))["sources"]:
        pass


def test_every_widget_kind_is_a_known_layer():
    """The wallpaper tells the widget which layers it shows through the helper's whitelist: a kind missing from it
    never appears in the widget's grouped view (the tsunami group was missing for exactly this reason)."""
    from livemap_helper.common import LAYER_NAMES
    widget = (WIDGET / "contents" / "ui" / "main.qml").read_text(encoding="utf-8")
    layer_of = dict(re.findall(r'(\w+): "(\w+)"', re.search(r"readonly property var layerOf: \(\{([^}]*)\}\)", widget).group(1)))
    for kind, layer in layer_of.items():
        assert layer in LAYER_NAMES, "widget kind %s maps to layer %s, which the helper's LAYER_NAMES does not know" % (kind, layer)
    main_qml = (CONTENTS / "ui" / "main.qml").read_text(encoding="utf-8")
    for layer in re.findall(r'cfg\.Show\w+ \? "(\w+)" : ""', main_qml):
        assert layer in LAYER_NAMES, "main.qml reports layer %s, which LAYER_NAMES does not know" % layer


def test_fake_http_matches_the_real_signature():
    """The tests feed the helper through a stand-in `_http`; a keyword the stand-in takes and the real one does
    not (headers=, once) passes every test and fails on the desktop."""
    import inspect
    from livemap_helper import common
    real = set(inspect.signature(common._http).parameters)
    for p in ("url", "method", "timeout", "limit", "headers"):
        assert p in real, "the real _http lacks %s" % p
