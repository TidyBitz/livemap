"""The feed parsers against recorded responses: a change in a site's format should fail here, not on a desktop."""
import json
import time

from conftest import fixture

from livemap_helper import fires, floods, storms, tsunami, volcanoes
from livemap_helper.common import storm_kind


# ---- storms ---------------------------------------------------------------------------------------------------
def test_jtwc_warning_positions_and_winds():
    now = time.mktime(time.strptime("2026-10-22 08:30", "%Y-%m-%d %H:%M"))
    lon, lat, wind, issued, dots = storms.jtwc_warning(fixture("jtwc_wp2926web.txt"), now)
    assert (lon, lat) == (126.0, 20.3)
    assert wind == round(115 * 1.852)
    assert [d[2] for d in dots] == [194, 176, 46]                  # 105, 95, 25 kt
    assert dots[0][:2] == [124.7, 21.3]
    assert time.gmtime(issued).tm_mday == 22 and time.gmtime(issued).tm_hour == 0


def test_jtwc_warning_skips_the_remarks():
    text = fixture("jtwc_wp2926web.txt")
    assert "REMARKS:" in text
    _lon, _lat, _wind, _issued, dots = storms.jtwc_warning(text, time.time())
    assert all(d[1] != 20.6 for d in dots)                         # the remarks' "220300Z POSITION NEAR 20.6N" is not a fix


def test_jtwc_rss_patterns():
    rss = ('Typhoon 29W (Champi) Warning #31 <a href="https://www.metoc.navy.mil/jtwc/products/wp2926web.txt">x</a>'
           'Tropical Cyclone 02S (Agueda) Warning #05 <a href="https://www.metoc.navy.mil/jtwc/products/sh0227web.txt">x</a>'
           'Tropical Storm 22E (Vance) <a href="https://www.metoc.navy.mil/jtwc/products/ep2226web.txt">x</a>')
    heads = [m.groups() for m in storms.JTWC_STORM_RE.finditer(rss)]
    assert heads[0] == ("Typhoon", "29W", "Champi") and heads[1][1] == "02S"
    assert [m.group(1) for m in storms.JTWC_PRODUCT_RE.finditer(rss)] == ["wp", "sh", "ep"]


def test_bdeck_one_fix_per_time_oldest_first():
    track = storms._parse_bdeck(fixture("bwp292026.dat"))
    assert len(track) == 5                                         # the 34/50 kt radii lines of one time collapse to one fix
    assert track[0][3] < track[-1][3]
    assert track[-1][:3] == [131.5, 16.5, round(140 * 1.852)]
    assert all(p[4] == 1 for p in track)                           # TD, TS, TY, ST are all tropical


def test_storm_kind_thresholds_and_basin_names():
    assert storm_kind(50, 20, 130) == ("Tropical depression", 0)
    assert storm_kind(100, 20, 130) == ("Tropical storm", 0)
    assert storm_kind(200, 20, 130) == ("Typhoon", 3)
    assert storm_kind(200, 20, -60) == ("Hurricane", 3)
    assert storm_kind(200, -20, 60) == ("Cyclone", 3)
    assert storm_kind(260, 20, -60)[1] == 5


# ---- tsunami --------------------------------------------------------------------------------------------------
def test_ptwc_information_statement():
    rec = tsunami.parse_tsunami_cap(fixture("ptwc_information.xml"), "PTWC")
    assert rec["level"] == 0 and rec["mag"] == 6.6 and rec["location"] == "Vanuatu"
    assert (rec["lat"], rec["lon"]) == (-13.869, 165.713)
    assert rec["url"].startswith("https://")
    assert rec["incident"] == "26293000"


def test_tsunami_levels():
    assert tsunami.tsunami_level("Tsunami Threat Message") == 3
    assert tsunami.tsunami_level("Tsunami Warning") == 3
    assert tsunami.tsunami_level("Tsunami Advisory") == 2
    assert tsunami.tsunami_level("Tsunami Watch") == 1
    assert tsunami.tsunami_level("Tsunami Information") == 0


def _threat_xml(sent, expires):
    return fixture("ptwc_threat.xml").replace("SENT", sent).replace("EXPIRES", expires)


def test_tsunami_memory_threat_then_stood_down(no_network):
    """tsunami.gov serves one message per centre: a threat must survive being overwritten by an information
    statement, and the information statement must stand it down."""
    from datetime import datetime, timezone
    now = time.time()
    iso = lambda t: datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S-00:00")
    no_network("PHEBCAP.xml", _threat_xml(iso(now - 600), iso(now + 3600)))
    no_network("PHEB.json", fixture("ptwc_threat.json"))
    no_network("PAAQCAP.xml", fixture("ptwc_information.xml").replace("2026-10-20T04:31:12", iso(now - 300)[:19]))
    d = tsunami.fetch_tsunami()
    active = [e for e in d["events"] if e["active"]]
    assert len(active) == 1 and active[0]["level"] == 3 and active[0]["areas"] == ["Panama", "Costa Rica"]
    assert len(active[0]["segments"]) == 1                         # the "Information" segment is not a threatened coast
    assert active[0]["segments"][0][0] == "Puerto Armuelles"
    # the centre's file is now an information statement for the same event
    info = fixture("ptwc_information.xml").replace("PHEB-1-26293000", "PHEB-2-26282000").replace("26293000", "26282000").replace("2026-10-20T04:31:12", iso(now)[:19])
    no_network("PHEBCAP.xml", info)
    d = tsunami.fetch_tsunami()
    ev = next(e for e in d["events"] if e["incident"] == "26282000")
    assert not ev["active"] and ev["ended"] and ev["peak"] == 3


# ---- floods ---------------------------------------------------------------------------------------------------
def test_nws_levels_filter_and_grouping(no_network):
    no_network("api.weather.gov/alerts/active", fixture("nws_alerts.json"))
    alerts = floods.fetch_nws_floods()
    assert sorted(a["event"] for a in alerts) == ["Flash Flood Warning", "Flood Warning", "Flood Warning"]   # the tornado and the test alert are not floods
    assert {a["alert"] for a in alerts} == {"red", "orange"}
    assert all(a["area"] for a in alerts) and all(a["lat"] for a in alerts)
    groups = floods.group_nws(alerts)
    assert len(groups) == 2                                        # per office and event: one flash flood warning, one flood warning
    fw = next(g for g in groups if g["event"] == "Flood Warning")
    assert fw["count"] == 2 and "Houston/Galveston TX" in fw["name"] and "Liberty" in fw["name"]
    assert fw["id"] == "nws:houston-galveston-tx-flood-warning"


# ---- wildfires ------------------------------------------------------------------------------------------------
def test_firms_viirs_confidence_letters_and_weighting():
    today = time.strftime("%Y-%m-%d", time.gmtime())
    cells = fires.cluster_hotspots(fixture("firms_viirs.csv").replace("DATE", today))
    by = {(c["lat"], c["lon"]): c for c in cells}
    hot = by[(-10.11, 30.21)]
    assert hot["raw"] == 3 and hot["n"] == 1                       # h, h, n count (0.4 each); l is below the confidence floor
    assert hot["frp"] == 38
    assert by[(45.0, -120.0)]["raw"] == 1


def test_firms_modis_still_parses():
    today = time.strftime("%Y-%m-%d", time.gmtime())
    cells = fires.cluster_hotspots(fixture("firms_modis.csv").replace("DATE", today))
    assert len(cells) == 1 and cells[0]["raw"] == 2                # the 40 % detection is dropped


def test_firms_preference_order():
    assert fires.FIRMS_FILES[0].startswith("noaa-21") and fires.FIRMS_FILES[1].startswith("noaa-20") and "MODIS" in fires.FIRMS_FILES[2]
    assert all(h.startswith("https://") for h in fires.FIRMS_HOSTS)


# ---- volcanoes ------------------------------------------------------------------------------------------------
def test_volcano_feed_names_coordinates_and_newness():
    rows, _tags = volcanoes.parse_volcano_feed(fixture("gvp_weekly.rss"))
    assert [r["name"] for r in rows] == ["Kilauea", "Etna"]        # the duplicate collapses
    k = rows[0]
    assert k["country"] == "United States" and k["new"] is True and (k["lat"], k["lon"]) == (19.421, -155.287)
    assert rows[1]["new"] is False and rows[1]["status"] == "continuing"


def test_volcano_report_table():
    table = volcanoes.report_table(fixture("gvp_weekly_table.html"))
    assert table["kilauea"][0] == "2024 Dec 23" and table["kilauea"][1].startswith("new")
    assert table["etna"][1].startswith("continuing")
    assert "yellowstone" in table


# ---- the feed's news bookkeeping -------------------------------------------------------------------------------
def test_history_seen_updated_and_reseed(data_dir):
    from livemap_helper import feed
    now = time.time()
    # a file from before the bookkeeping: a launch five days out and a quake two hours ago
    feed.HISTORY.write_text(json.dumps({"items": {"l1": {"kind": "launch", "when": now + 5 * 86400, "title": "Falcon", "future": True, "level": 1},
                                                  "q1": {"kind": "quake", "when": now - 7200, "title": "M4.7", "level": 1}}}))
    items = [{"kind": "launch", "when": now + 5 * 86400, "title": "Falcon", "future": True, "level": 1, "key": "l1"},
             {"kind": "quake", "when": now - 7200, "title": "M4.7", "level": 1, "key": "q1"},
             {"kind": "quake", "when": now - 1800, "title": "M5.1", "level": 2, "key": "q2"},
             {"kind": "sat", "when": now, "title": "ISS", "pin": True}]
    feed.remember_history(items, now)
    order = [it["title"] for it in sorted(items, key=lambda it: (1 if it.get("pin") else 0, -(it["updated"] or it["when"])))]
    assert order == ["M5.1", "M4.7", "Falcon", "ISS"]              # news first, the planned launch behind the day's quakes, satellites last
    assert json.loads(feed.HISTORY.read_text())["news"] == feed.HISTORY_MARK
    items[0]["level"] = 2                                          # the launch enters its last hour
    feed.remember_history(items, now + 10)
    assert items[0]["updated"] == now + 10
