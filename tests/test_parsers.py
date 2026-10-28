"""The feed parsers against recorded responses: a change in a site's format should fail here, not on a desktop."""
import json
import time

from conftest import fixture

from livemap_helper import fires, floods, storms, tsunami, volcanoes
from livemap_helper.common import storm_kind


# ---- storms ---------------------------------------------------------------------------------------------------
def test_jtwc_warning_positions_and_winds():
    now = time.mktime(time.strptime("2026-10-22 08:30", "%Y-%m-%d %H:%M"))
    lon, lat, wind, issued, dots, hours = storms.jtwc_warning(fixture("jtwc_wp2926web.txt"), now)
    assert hours == [12, 24, 96]
    assert (lon, lat) == (126.0, 20.3)
    assert wind == round(115 * 1.852)
    assert [d[2] for d in dots] == [194, 176, 46]                  # 105, 95, 25 kt
    assert dots[0][:2] == [124.7, 21.3]
    assert time.gmtime(issued).tm_mday == 22 and time.gmtime(issued).tm_hour == 0


def test_jtwc_warning_skips_the_remarks():
    text = fixture("jtwc_wp2926web.txt")
    assert "REMARKS:" in text
    _lon, _lat, _wind, _issued, dots, _hours = storms.jtwc_warning(text, time.time())
    assert all(d[1] != 20.6 for d in dots)                         # the remarks' "220300Z POSITION NEAR 20.6N" is not a fix


def test_jtwc_rss_patterns():
    rss = ('Typhoon 29W (Champi) Warning #31 <a href="https://www.metoc.navy.mil/jtwc/products/wp2926web.txt">x</a>'
           'Tropical Cyclone 02S (Agueda) Warning #05 <a href="https://www.metoc.navy.mil/jtwc/products/sh0227web.txt">x</a>'
           'Tropical Storm 22E (Vance) <a href="https://www.metoc.navy.mil/jtwc/products/ep2226web.txt">x</a>')
    heads = [m.groups() for m in storms.JTWC_STORM_RE.finditer(rss)]
    assert heads[0] == ("Typhoon", "29W", "Champi") and heads[1][1] == "02S"
    assert [m.group(1) for m in storms.JTWC_PRODUCT_RE.finditer(rss)] == ["wp", "sh", "ep"]


def test_estimated_cone_widens_with_lead_time():
    from livemap_helper.common import _in_ring
    dots = [[124.7, 21.3, 194], [123.7, 22.8, 176], [122.9, 24.8, 157], [123.1, 26.8, 120]]
    ring = storms.estimated_cone(126.0, 20.3, dots, [12, 24, 36, 48])
    assert len(ring) >= 40 and ring[:2] != ring[-2:] or ring[:2] == ring[-2:]
    assert _in_ring(124.7, 21.3, ring) and _in_ring(123.1, 26.8, ring)      # every forecast point lies inside
    assert _in_ring(123.1 + 1.5, 26.8, ring) and not _in_ring(124.7 + 1.5, 21.3, ring)   # wide at 48 h, narrow at 12 h
    assert storms.estimated_cone(126.0, 20.3, [], []) == []


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


# ---- official flood warnings beyond the US ------------------------------------------------------------------
def _soon(hours):
    from datetime import datetime, timedelta, timezone
    return (datetime.now(timezone.utc) + timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%S+00:00")


def test_meteoalarm_flood_types_levels_and_placement():
    from livemap_helper import warnings as w
    body = json.loads(fixture("meteoalarm_italy.json").replace("EFFECTIVE", _soon(-1)).replace("EXPIRES", _soon(6)))
    alerts = w.parse_meteoalarm(body, "italy")
    events = {a["name"]: a for a in alerts}
    assert "Piemonte" not in events                                  # wind is not this layer's
    assert "Sardegna" not in events                                  # green is no warning
    lig = events["Liguria"]
    assert lig["alert"] == "orange" and lig["event"] == "Rain and Flood Warning" and lig["office"] == "Italy"
    assert 43.5 < lig["lat"] < 45 and 7 < lig["lon"] < 10.5         # placed on Natural Earth's Liguria
    assert lig["area"], "the region's rings come along as the area"
    vda = events["Valle d'Aosta; Nowhere Special"]
    assert vda["alert"] == "green" and vda["counties"] == 2 and 45 < vda["lat"] < 46.5   # the unknown area is ignored, the known one places it


def test_meteoalarm_region_lookup_handles_accents_and_variants():
    from livemap_helper import warnings as w
    assert w.place_region("IT", "Valle d'Aosta") is not None
    assert w.place_region("ES", "Andalucía") is not None
    assert w.place_region("DE", "Bayern") is not None
    assert w.place_region("FR", "No Such Region Anywhere") is None


def test_eccc_flood_filter_and_levels():
    from livemap_helper import warnings as w
    body = json.loads(fixture("eccc_alerts.json").replace("2026-10-23T20:00:00Z", _soon(6)))
    alerts = w.parse_eccc(body)
    names = {a["name"]: a for a in alerts}
    assert "Toronto" not in names                                     # snow is not this layer's
    assert names["Metro Vancouver"]["alert"] == "orange" and names["Metro Vancouver"]["event"] == "Rainfall Warning"
    assert names["Saint John"]["alert"] == "green"
    assert names["Metro Vancouver"]["area"] and -123.4 < names["Metro Vancouver"]["lon"] < -122.8


def test_ea_levels_and_area_cache(no_network, data_dir):
    from livemap_helper import warnings as w
    no_network("floodAreas/065WAF4Ouse/polygon", fixture("ea_area.json"))
    no_network("floodAreas/122FWF123/polygon", fixture("ea_area.json").replace("-1.10", "-2.80").replace("-1.05", "-2.70"))
    alerts = w.parse_ea(json.loads(fixture("ea_floods.json")))
    by = {a["id"]: a for a in alerts}
    assert "ea:gone" not in by                                        # no longer in force
    assert by["ea:065waf4ouse"]["alert"] == "orange" and 53.9 < by["ea:065waf4ouse"]["lat"] < 54.01
    assert by["ea:122fwf123"]["alert"] == "red" and by["ea:122fwf123"]["office"] == "West Midlands"
    assert (data_dir / "ea-areas" / "065WAF4Ouse.json").exists()     # fetched once, kept
    no_network("floodAreas/065WAF4Ouse/polygon", "not json at all")
    again = w.parse_ea(json.loads(fixture("ea_floods.json")))
    assert len(again) == 2                                           # served from the cache, the broken response never read


def test_official_floods_mask_and_grouping(no_network, monkeypatch):
    from livemap_helper import floods, warnings as w
    no_network("api.weather.gov/alerts/active", fixture("nws_alerts.json"))
    body = fixture("meteoalarm_italy.json").replace("EFFECTIVE", _soon(-1)).replace("EXPIRES", _soon(6))
    for slug in w.METEOALARM_COUNTRIES:
        no_network("feeds-" + slug, body if slug == "italy" else '{"warnings": []}')
    alerts, note = floods.official_floods(1 | 2)
    assert note == ""
    assert {a["source"] for a in alerts} == {"nws", "meteoalarm"}
    groups = floods.group_nws(alerts)
    it = [g for g in groups if g["office"] == "Italy"]
    assert len(it) == 2 and all(g["url"].startswith("https://www.meteoalarm.org") for g in it)
    only_us, _ = floods.official_floods(1)
    assert {a["source"] for a in only_us} == {"nws"}


# ---- earthquakes: EMSC merged with USGS ---------------------------------------------------------------------
def test_emsc_parse_and_merge():
    from livemap_helper import quakes
    from datetime import datetime, timezone
    t = time.time() - 600
    iso = datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.0Z")
    emsc = quakes.parse_emsc(json.loads(fixture("emsc.json").replace("TIME1", iso).replace("TIME2", iso)))
    assert len(emsc) == 2 and emsc[0]["properties"]["source"] == "EMSC" and emsc[0]["properties"]["place"] == "Near The Coast Of Panama"
    assert emsc[0]["geometry"]["coordinates"][:2] == [-82.7, 8.1] and abs(emsc[0]["properties"]["time"] / 1000 - t) < 1
    usgs = [{"type": "Feature", "id": "us7000abcd", "properties": {"mag": 4.7, "place": "Panama", "time": int((t + 30) * 1000), "source": "USGS"},
             "geometry": {"type": "Point", "coordinates": [-82.5, 8.2, 12]}}]
    merged = quakes.merge(usgs, emsc)
    assert len(merged) == 2                                          # the Panama quake is one event; the Italian M3.1 is new
    assert [f["properties"]["source"] for f in merged] == ["USGS", "EMSC"]


def test_quakes_cache_survives_a_source_outage(no_network, data_dir):
    from livemap_helper import quakes
    from datetime import datetime, timezone
    iso = datetime.fromtimestamp(time.time() - 60, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.0Z")
    no_network("earthquake.usgs.gov", json.dumps({"type": "FeatureCollection", "features": []}))
    no_network("seismicportal.eu", fixture("emsc.json").replace("TIME1", iso).replace("TIME2", iso))
    features, problems = quakes.quakes_cached("4.5_day", 3, max_age=0)
    assert len(features) == 2 and problems == []
    no_network("earthquake.usgs.gov", "<html>down</html>")
    features, problems = quakes.quakes_cached("4.5_day", 3, max_age=0)
    assert len(features) == 2 and any("USGS" in p for p in problems)   # EMSC still answers, USGS's part comes from the cache


def test_geonet_raised_levels_only_and_merge_into_the_report():
    from livemap_helper import volcanoes
    alerts = volcanoes.parse_geonet(json.loads(fixture("geonet_val.json")))
    assert [a["name"] for a in alerts] == ["Whakaari/White Island", "Ruapehu"]   # Taupō at level 0 is not raised
    assert alerts[0]["alert"] == "yellow" and alerts[0]["level"] == "Level 2"
    rows, _tags = volcanoes.parse_volcano_feed(fixture("gvp_weekly.rss"))
    merged = volcanoes.merge_usgs_alerts(rows, alerts)
    wi = next(r for r in merged if r["name"].startswith("Whakaari"))
    assert wi["country"] == "New Zealand" and wi["alert"] == "yellow" and wi["lat"] == -37.521


# ---- volcanoes: JMA levels and VAAC ash advisories ------------------------------------------------------------
def test_jma_levels_by_japanese_name():
    from livemap_helper import volcanoes
    alerts = volcanoes.parse_jma(json.loads(fixture("jma_warning.json")))
    by = {a["name"]: a for a in alerts}
    assert set(by) == {"Meakandake", "Sakurajima"}                 # Fuji at level 1 is not raised
    assert by["Meakandake"]["alert"] == "yellow" and by["Meakandake"]["level"] == "Level 2" and by["Meakandake"]["lat"] == 43.3864
    assert by["Sakurajima"]["alert"] == "orange" and by["Sakurajima"]["observatory"] == "JMA"
    rows, _ = volcanoes.parse_volcano_feed(fixture("gvp_weekly.rss"))
    merged = volcanoes.merge_usgs_alerts(rows, alerts)
    assert next(r for r in merged if r["name"] == "Sakurajima")["country"] == "Japan"


def test_vaac_index_and_advisory(no_network, data_dir):
    from livemap_helper import vaac, volcanoes
    from datetime import datetime, timezone
    names = vaac.parse_vaac_index(fixture("vaac_index.html"))
    assert names == ["FVXX21_20261023_0951", "FVXX21_20261023_0345", "FVXX22_20261023_0220"]   # once each, case-folded
    issued = datetime.fromtimestamp(time.time() - 1800, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    rec = vaac.parse_vaac_xml(fixture("vaac_advisory.xml").replace("ISSUED", issued), "FVXX21_20261023_0951")
    assert rec["name"] == "Reventador" and rec["number"] == "352010" and rec["country"] == "Ecuador"
    assert (rec["lat"], rec["lon"]) == (-0.0772, -77.6558) and rec["top_fl"] == 150
    assert len(rec["observed"]) == 1 and len(rec["forecast"]) == 1 and rec["observed"][0][:2] == [-77.66, -0.07]   # lon, lat
    # the whole fetch: index, then each advisory once, remembered
    no_network("vaac/messages.html", fixture("vaac_index.html"))
    no_network("FVXX21_20261023_0951.xml", fixture("vaac_advisory.xml").replace("ISSUED", issued))
    no_network("FVXX21_20261023_0345.xml", fixture("vaac_advisory.xml").replace("ISSUED", issued).replace("2026/1113", "2026/1112"))
    no_network("FVXX22_20261023_0220.xml", "<broken")
    d = vaac.fetch_vaac()
    assert [a["name"] for a in d["advisories"]] == ["Reventador"] and d["advisories"][0]["count"] == 2
    assert d["advisories"][0]["advisory"] == "2026/1113"            # the latest of the two
    assert (data_dir / "vaac.json").exists()
    no_network("FVXX21_20261023_0951.xml", "must not be fetched again")
    d2 = vaac.fetch_vaac()
    assert d2["advisories"][0]["advisory"] == "2026/1113"
    rows, _ = volcanoes.parse_volcano_feed(fixture("gvp_weekly.rss"))
    merged = vaac.merge_vaac(rows, d2["advisories"])
    rev = next(r for r in merged if r["name"] == "Reventador")
    assert rev["ash_top_fl"] == 150 and rev["ash"] is True and rev["status"] == "ash advisory"


def test_feed_facts_and_pictures():
    """The widget's bubble: facts rows carry no empty values, and the picture address follows the centre's pattern."""
    from livemap_helper.feed import facts_for, storm_image
    q = facts_for("quake", {"properties": {"mag": 5.1, "magType": "mww", "time": 1760000000000, "felt": 12, "cdi": 4.2, "alert": "green", "source": "USGS", "status": "reviewed"},
                            "geometry": {"coordinates": [14.2, 38.7, 10.0]}})
    labels = [row[0] for row in q["facts"]]
    assert "Depth" in labels and "Felt" in labels and "PAGER alert" in labels and "Tsunami" not in labels
    assert all(row[1] for row in q["facts"]) and q["image"] == ""
    when = [row for row in q["facts"] if row[0] == "When"][0]
    assert len(when) == 3 and abs(when[2] - 1760000000) < 1          # a time row carries its timestamp for the widget's "ago"
    assert storm_image({"id": "al082026", "source": "NHC"}) == "https://www.nhc.noaa.gov/storm_graphics/AT08/refresh/AL082026_5day_cone_with_line_and_wind_sm2+png/"
    assert storm_image({"id": "wp2526", "source": "JTWC"}) == "https://www.metoc.navy.mil/jtwc/products/wp2526.gif"
    assert storm_image({"id": "1001234", "source": "GDACS"}) == ""
    st = facts_for("storm", {"kind": "Typhoon", "cat": 2, "lat": 18.4, "lon": 134.2, "hours": 0.5, "source": "JTWC", "id": "wp2526", "cone_estimated": True},
                   {"wind": "109 mph (peak)", "ahead": "Aichi Minamihama refinery, +7", "crossed": ""})
    fix = [row for row in st["facts"] if row[0] == "Last fix"][0]
    assert ["Position", "18.4°N 134.2°E"] in st["facts"] and len(fix) == 3 and abs(fix[2] - (time.time() - 1800)) < 5 and st["image"].endswith("wp2526.gif")
    assert not any(row[0] == "Crossed" for row in st["facts"])
    L = facts_for("launch", {"rocket": "Falcon 9", "mission": "Starlink", "orbit": "LEO", "provider": "SpaceX", "pad": "SLC-4E", "site": "Vandenberg", "net": 1760000000, "status_name": "Go for Launch", "image": "https://x/y.png"})
    assert L["image"] == "https://x/y.png" and ["Pad", "SLC-4E, Vandenberg"] in L["facts"]


def test_spacecraft_facts_and_art():
    from livemap_helper.feed import sat_facts
    for short in ("ISS", "Hubble", "Tiangong"):
        f = sat_facts(short, {})
        assert f["facts"][0][0] == "About" and f["image"].endswith("/images/%s.png" % short.lower()), short
    iss = {"ISS": ["ISS (ZARYA)", "1 25544U 98067A   26296.50000000  .00016717  00000-0  10270-3 0  9000",
                   "2 25544  51.6400 208.9163 0006703 130.5360 325.0288 15.49000000000000"]}
    f = sat_facts("ISS", iss)
    labels = [k for k, v in f["facts"]]
    assert "Over" in labels and "Altitude" in labels and "One orbit" in labels
    alt_km = dict(f["facts"])["Altitude"]
    alt_mi = dict(sat_facts("ISS", iss, None, (1, 1))["facts"])["Altitude"]
    assert alt_km.endswith(" km") and alt_mi.endswith(" mi") and float(alt_mi.split()[0]) < float(alt_km.split()[0])
    assert "mph" in dict(sat_facts("ISS", iss, None, (1, 1))["facts"])["Speed"]


def test_quake_pictures_and_snapshots(no_network, data_dir, monkeypatch):
    import json
    from livemap_helper import feed
    monkeypatch.setattr(feed, "QUAKE_PICTURES", data_dir / "quake-pictures.json")
    no_network("detail/us1.geojson", json.dumps({"properties": {"products": {"shakemap": [{"contents": {"download/intensity.jpg": {"url": "https://earthquake.usgs.gov/x/intensity.jpg"}}}]}}}))
    no_network("detail/us2.geojson", json.dumps({"properties": {"products": {}}}))
    import time as _t
    old = _t.time() - 3 * 86400                                        # old quakes: a miss waits six hours
    pics = feed.quake_pictures([("us1", old), ("us2", old), ("emsc123", old)])
    assert pics["us1"].endswith("intensity.jpg") and pics["us2"] == "" and "emsc123" not in pics
    # a second run asks for nothing new (us1 is kept for good, us2 waits six hours) - the fake serves nothing else
    pics2 = feed.quake_pictures([("us%d" % i, old) for i in range(1, 8)])
    assert pics2["us1"] == pics["us1"] and len([k for k in pics2 if k.startswith("us") and k not in ("us1", "us2")]) <= feed.LOOKUPS_PER_RUN
    url = feed.satellite_snapshot(18.4, 134.2, now=1792764800)   # 2026-10-23 14:13 UTC: evening in the western Pacific, the afternoon pass is in -> today
    assert url.startswith("https://wvs.earthdata.nasa.gov/api/v1/snapshot?") and "BBOX=13.40,127.20,23.40,141.20" in url and "TIME=2026-10-23" in url
    assert feed.storm_image({"id": "1001342", "source": "GDACS", "lat": 40.0, "lon": -65.8}).startswith("https://wvs.earthdata.nasa.gov/")


def test_crews_from_ll2(no_network, data_dir, monkeypatch):
    import json
    from livemap_helper import space
    monkeypatch.setattr(space, "ASTRONAUTS", data_dir / "astronauts.json")
    no_network("astronaut/?in_space=true", json.dumps({"results": [
        {"name": "Jane Doe", "nationality": "American", "agency": {"abbrev": "NASA", "country_code": "USA"}, "last_flight": "2026-08-01T12:00:00Z"},
        {"name": "Li Wei", "nationality": "Chinese", "agency": {"abbrev": "CMSA", "country_code": "CHN"}, "last_flight": "2026-04-24T09:00:00Z"},
        {"name": "Ivan Petrov", "nationality": "Russian", "agency": {"abbrev": "RFSA", "country_code": "RUS"}, "last_flight": "2026-09-27T00:00:00Z"},
        {"name": "Starman", "nationality": "Earthling", "agency": {"abbrev": "SpX", "country_code": "USA"}, "last_flight": "2018-02-06T20:45:00Z"},
        {"name": "Lost Probe", "nationality": "American", "agency": {"abbrev": "NASA", "country_code": "USA"}, "last_flight": "2021-01-01T00:00:00Z"}]}))
    crews = space.fetch_crews()
    assert [c["name"] for c in crews["ISS"]] == ["Jane Doe", "Ivan Petrov"] and crews["Tiangong"][0]["name"] == "Li Wei"
    assert crews["ISS"][0]["days"] > 60 and crews["ISS"][0]["country"] == "American" and crews["ISS"][0]["flag"] == "\U0001F1FA\U0001F1F8"
    from livemap_helper.space import flag_for
    assert flag_for("Chinese") == "\U0001F1E8\U0001F1F3" and flag_for("", "RUS") == "\U0001F1F7\U0001F1FA" and flag_for("Martian", "AUT,BEL,FRA") == ""
    from livemap_helper.feed import sat_facts
    f = sat_facts("ISS", {}, crews)
    aboard = [v for k, v in f["facts"] if k.startswith("Aboard") or k == " "]
    assert len(aboard) == 2 and aboard[0].startswith("Jane Doe · American \U0001F1FA\U0001F1F8 · ") and "days" in aboard[0]
    assert not [v for k, v in sat_facts("Hubble", {}, crews)["facts"] if k.startswith("Aboard")]


def test_tsunami_twins_merge():
    from livemap_helper.tsunami import merge_twins
    a = {"centre": "PTWC", "incident": "1", "mag": 7.2, "lat": -15.2, "lon": 167.1, "sent": 1000, "level": 0, "active": False, "areas": [], "segments": [], "url": "u1", "event": "Tsunami Information"}
    b = {"centre": "NTWC", "incident": "9", "mag": 7.2, "lat": -15.3, "lon": 167.0, "sent": 1060, "level": 1, "active": True, "areas": ["Hawaii"], "segments": [[1, 2]], "url": "u2", "event": "Tsunami Advisory"}
    c = {"centre": "PTWC", "incident": "2", "mag": 6.1, "lat": 38.0, "lon": 142.0, "sent": 1100, "level": 0, "active": False, "areas": [], "segments": [], "url": "u3", "event": "Tsunami Information"}
    out = merge_twins([a, b, c])
    assert len(out) == 2
    m = [e for e in out if e["mag"] == 7.2][0]
    assert m["centre"] == "NTWC · PTWC" and m["level"] == 1 and m["active"] and m["areas"] == ["Hawaii"] and m["segments"] == [[1, 2]] and m["twin_url"] == "u1"


def test_alert_history_spans(data_dir, monkeypatch):
    from livemap_helper import alerts
    monkeypatch.setattr(alerts, "ALERTS_HISTORY", data_dir / "hist.json")
    t0 = 1_792_800_000
    alerts.remember_alert_history({"UA-32": {"status": "A", "since": t0, "first_seen": t0}}, t0 + 60)
    alerts.remember_alert_history({"UA-32": {"status": "A", "since": t0, "first_seen": t0, "renewed": t0 + 1800}}, t0 + 1900)
    alerts.remember_alert_history({"UA-32": {"status": "C", "since": t0, "ended": t0 + 3600}}, t0 + 3660)
    alerts.remember_alert_history({"UA-32": {"status": "A", "since": t0 + 7200, "first_seen": t0 + 7200}}, t0 + 7260)
    import json
    h = json.loads((data_dir / "hist.json").read_text())
    assert [sp[:2] for sp in h["UA-32"]] == [[t0, t0 + 3600], [t0 + 7200, None]] and h["UA-32"][0][2] == t0 + 1800
    monkeypatch.setattr(alerts, "ua_regions", lambda: [{"code": "UA-32", "name": "Kyiv", "lat": 50, "lon": 30}])
    import time
    monkeypatch.setattr(time, "time", lambda: t0 + 7500)
    rows = alerts.alert_history(6)["rows"]
    assert len(rows) == 1 and rows[0]["name"] == "Kyiv" and rows[0]["active"] and len(rows[0]["spans"]) == 2 and rows[0]["on_minutes"] == 60


def test_fetch_json_says_what_came_back(no_network):
    """A source answering with XML or HTML must name its own error, not 'Expecting value: line 1 column 1'."""
    from livemap_helper.common import fetch_json
    no_network("example.org/ogc", '<?xml version="1.0"?><ows:ExceptionReport><ows:Exception exceptionCode="InvalidParameterValue" locator="typename">'
                                  '<ows:ExceptionText>msWFSGetFeature(): WFS server error. TYPENAME \'ALERTS\' doesn\'t exist in this server.</ows:ExceptionText></ows:Exception></ows:ExceptionReport>')
    no_network("example.org/down", "<html><head><title>503 Service Unavailable</title></head><body>later</body></html>")
    no_network("example.org/ok", '{"a": 1}')
    assert fetch_json("https://example.org/ok") == {"a": 1}
    try:
        fetch_json("https://example.org/ogc", what="ECCC")
    except ValueError as e:
        assert "ECCC: not JSON" in str(e) and "TYPENAME 'ALERTS' doesn't exist" in str(e)
    else:
        raise AssertionError("no error for XML")
    try:
        fetch_json("https://example.org/down")
    except ValueError as e:
        assert "503 Service Unavailable" in str(e)


def test_eccc_gml_is_read():
    from livemap_helper.warnings import gml_features, parse_eccc
    gml = '''<?xml version='1.0' encoding="UTF-8" ?>
<wfs:FeatureCollection xmlns:ec-msc="urn:x-msc-smc:md:weather-meteo" xmlns:gml="http://www.opengis.net/gml/3.2" xmlns:wfs="http://www.opengis.net/wfs/2.0">
 <wfs:member>
  <ec-msc:Current-Alerts gml:id="Current-Alerts.1">
   <gml:boundedBy><gml:Envelope srsName="urn:ogc:def:crs:EPSG::4326"><gml:lowerCorner>49 -124</gml:lowerCorner><gml:upperCorner>50 -122</gml:upperCorner></gml:Envelope></gml:boundedBy>
   <ec-msc:msGeometry><gml:Polygon srsName="urn:ogc:def:crs:EPSG::4326" gml:id="p1"><gml:exterior><gml:LinearRing><gml:posList srsDimension="2">49.0 -124.0 50.0 -124.0 50.0 -122.0 49.0 -122.0 49.0 -124.0</gml:posList></gml:LinearRing></gml:exterior></gml:Polygon></ec-msc:msGeometry>
   <ec-msc:identifier>urn:oid:2.49.0.1.124.1</ec-msc:identifier>
   <ec-msc:area>Metro Vancouver</ec-msc:area>
   <ec-msc:alert_type>rainfall warning</ec-msc:alert_type>
   <ec-msc:headline>RAINFALL WARNING IN EFFECT</ec-msc:headline>
   <ec-msc:expires>2099-01-01T00:00:00Z</ec-msc:expires>
  </ec-msc:Current-Alerts>
 </wfs:member>
 <wfs:member>
  <ec-msc:Current-Alerts gml:id="Current-Alerts.2">
   <ec-msc:msGeometry><gml:Polygon srsName="urn:ogc:def:crs:EPSG::4326" gml:id="p2"><gml:exterior><gml:LinearRing><gml:posList>45 -75 46 -75 46 -74 45 -74 45 -75</gml:posList></gml:LinearRing></gml:exterior></gml:Polygon></ec-msc:msGeometry>
   <ec-msc:identifier>urn:oid:2.49.0.1.124.2</ec-msc:identifier>
   <ec-msc:area>Ottawa</ec-msc:area>
   <ec-msc:alert_type>wind warning</ec-msc:alert_type>
   <ec-msc:expires>2099-01-01T00:00:00Z</ec-msc:expires>
  </ec-msc:Current-Alerts>
 </wfs:member>
</wfs:FeatureCollection>'''
    fc = gml_features(gml)
    assert len(fc["features"]) == 2 and fc["features"][0]["properties"]["area"] == "Metro Vancouver"
    assert fc["features"][0]["geometry"]["coordinates"][0][0][0] == (-124.0, 49.0)        # lon, lat
    out = parse_eccc(fc)
    assert len(out) == 1 and out[0]["name"] == "Metro Vancouver" and out[0]["alert"] == "orange" and 49.0 <= out[0]["lat"] <= 50.0 and -124.0 <= out[0]["lon"] <= -122.0
    try:
        gml_features('<?xml version="1.0"?><ows:ExceptionReport xmlns:ows="http://www.opengis.net/ows/1.1"><ows:Exception><ows:ExceptionText>TYPENAME nope</ows:ExceptionText></ows:Exception></ows:ExceptionReport>')
    except ValueError as e:
        assert "TYPENAME nope" in str(e)
    else:
        raise AssertionError("an exception report must raise")


def test_iss_passes_are_found_and_visibility_is_physical():
    """Denver, a real ISS element set: about six passes a day, ten minutes each; the visible ones only in the
    evening or before dawn (sky dark, station still lit); a pass at local noon is never 'visible'."""
    from livemap_helper import passes
    from livemap_helper.space import parse_tle
    el = parse_tle("1 25544U 98067A   26298.50000000  .00016717  00000-0  10270-3 0  9000",
                   "2 25544  51.6400 208.9163 0006703 130.5360 325.0288 15.49000000000000")
    t0 = 1792900000
    ps = passes.find_passes(el, 39.74, -104.99, t0, 2)
    assert 8 <= len(ps) <= 16 and all(300 <= p["duration"] <= 720 for p in ps)
    assert all(p["max_el"] >= passes.MIN_PEAK for p in ps)
    for p in ps:
        hour_local = ((p["peak"] - 6 * 3600) % 86400) / 3600          # MDT
        if p["visible"]:
            assert hour_local < 7 or hour_local > 17, hour_local        # only around dusk or dawn
        if 10 < hour_local < 15:
            assert not p["visible"]
    assert passes.compass(0) == "N" and passes.compass(247) == "WSW"
    assert passes.elevation_of_sun(39.74, -104.99, 1792900000 + 19 * 3600) > 0      # ~13:00 MDT: the sun is up


def test_flood_places_listed_in_the_bubble():
    from livemap_helper.feed import facts_for
    f = facts_for("flood", {"source": "nws", "alert": "orange", "event": "Coastal Flood Warning", "name": "3 counties · Miami FL",
                            "places": ["Coastal Miami-Dade", "Coastal Broward", "Coastal Palm Beach"], "onset": 1792900000, "until": 1793000000},
                  {"by": "NWS Miami FL"})
    row = [r for r in f["facts"] if r[0] == "3 counties"][0]
    assert row[1].count("•") == 3 and "Coastal Broward" in row[1]
    f = facts_for("flood", {"source": "ea", "alert": "green", "event": "Flood alert", "name": "Kent, South London and East Sussex", "places": ["Kent", "East Sussex"]}, {"by": "Environment Agency"})
    assert ["2 areas", "• Kent\n• East Sussex"] in [r[:2] for r in f["facts"]]


def test_live_url_page_reading():
    from livemap_helper.live import video_from_page
    assert video_from_page("https://www.youtube.com/watch?v=ROboUHfPUrU", "") == "ROboUHfPUrU"
    page = '<html><link rel="canonical" href="https://www.youtube.com/watch?v=M3HKLzjvKPc"><body>'
    assert video_from_page("https://www.youtube.com/@NASA/live", page) == "M3HKLzjvKPc"
    page = '{"videoId":"aaaaaaaaaaa","title":"old"} ... {"videoId":"bbbbbbbbbbb","isLiveNow":true}'
    assert video_from_page("https://www.youtube.com/@sen/live", page) == "bbbbbbbbbbb"
    assert video_from_page("https://www.youtube.com/@sen", "<html>nothing</html>") == ""


def test_sky_document_from_open_meteo(monkeypatch):
    """The Sky tab's document from a recorded-shape Open-Meteo answer: units, strips, bubble lines, ages."""
    import time as _t
    from livemap_helper import sky
    now = 1793034000                              # 2026-10-26 ~ 18:20 UTC = 12:20 Denver
    day0 = 1792994400                             # 2026-10-26 00:00 MDT (UTC-6)
    hours = [day0 + h * 3600 for h in range(24 * 7)]
    import math
    temps = [8 + 10 * math.sin((h % 24 - 6) / 24 * 2 * math.pi) for h in range(24 * 7)]
    fc = {"timezone": "America/Denver", "utc_offset_seconds": -21600,
          "current": {"time": now, "temperature_2m": 12.2, "apparent_temperature": 10.5, "relative_humidity_2m": 31, "pressure_msl": 1019.8,
                      "wind_speed_10m": 13, "wind_direction_10m": 315, "weather_code": 0, "cloud_cover": 5, "is_day": 1},
          "hourly": {"time": hours, "temperature_2m": temps, "precipitation_probability": [70 if 48 + 13 <= i <= 48 + 21 else 0 for i in range(168)],
                     "precipitation": [1.2 if 48 + 13 <= i <= 48 + 21 else 0 for i in range(168)], "snowfall": [0] * 168,
                     "weather_code": [61 if 48 + 13 <= i <= 48 + 21 else 1 for i in range(168)], "cloud_cover": [10] * 168,
                     "wind_speed_10m": [12] * 168, "wind_direction_10m": [300] * 168, "is_day": [1 if 7 <= i % 24 < 18 else 0 for i in range(168)],
                     "relative_humidity_2m": [30] * 168, "pressure_msl": [1018 + i * 0.1 for i in range(168)]},
          "daily": {"time": [day0 + d * 86400 for d in range(7)], "weather_code": [0, 2, 61, 71, 3, 0, 0],
                    "temperature_2m_max": [16, 14, 9, 3, 5, 11, 14], "temperature_2m_min": [3, 2, 1, -4, -5, -2, 0],
                    "precipitation_probability_max": [0, 10, 70, 80, 20, 0, 0], "precipitation_sum": [0, 0, 9.6, 4, 0.5, 0, 0], "snowfall_sum": [0, 0, 0, 5, 0, 0, 0],
                    "sunrise": [day0 + d * 86400 + 7 * 3600 + 21 * 60 for d in range(7)], "sunset": [day0 + d * 86400 + 18 * 3600 + 3 * 60 for d in range(7)],
                    "uv_index_max": [4] * 7}}
    cache = {"forecast": {"at": now, "good_at": now - 240, "data": fc},
             "air": {"at": now, "good_at": now - 6600, "data": {"current": {"us_aqi": 34, "european_aqi": 20}}},
             "kp": {"at": now, "good_at": now - 720, "data": {"kp": 2.33, "time": "x"}}}
    from livemap_helper import feed
    monkeypatch.setattr(feed, "home_passes", lambda now, mode: ([], None))
    doc = sky.build(39.74, -104.99, [1, 1, 1, 0], cache, now)      # miles, mph, 12-hour, temperature follows -> °F
    assert doc["now"]["temp"] == "54°F" and doc["now"]["wind"] == "8 mph NW" and doc["now"]["pressure"] == "30.11 in"
    assert doc["ages"]["forecast"]["age"] == "as of 4 min ago" and doc["ages"]["air"]["minutes"] == 110
    assert len(doc["days"]) == 7 and len(doc["days"][0]["cells"]) == 24 and doc["days"][0]["name"] == "Today"
    wed = doc["days"][2]
    assert wed["chance"] == "70 %" and wed["cells"][15]["p"] == 0.7 and wed["cells"][15]["mm"] == 1.2 and wed["cells"][3]["p"] == 0
    assert "1 PM" in wed["lines"][13] and "Light rain" in wed["lines"][13] and "0.05 in" in wed["lines"][13]
    assert doc["sun"]["sunrise"] == "7:21 AM" and doc["sun"]["sunset"] == "6:03 PM" and doc["sun"]["day_length"] == "10 h 42 min"
    assert "aurora" in doc["tonight"]["kp"] and doc["tonight"]["air"] == "US AQI 34, good"
    assert abs(doc["now_h"] - 11) < 0.01
    # Open-Meteo's daily stamps are the local date as if it were UTC (here: shifted by the offset): nothing may move
    fc["daily"]["time"] = [t - 21600 for t in fc["daily"]["time"]]
    doc_s = sky.build(39.74, -104.99, [1, 1, 1, 0], cache, now)
    assert abs(doc_s["now_h"] - 11) < 0.01 and doc_s["days"][2]["cells"][15]["p"] == 0.7 and abs(doc_s["days"][0]["sunrise_h"] - 7.35) < 0.01
    fc["daily"]["time"] = [t + 21600 for t in fc["daily"]["time"]]
    doc_c = sky.build(39.74, -104.99, [0, 0, 0, 0], cache, now)      # km, 24-hour, °C
    assert doc_c["now"]["temp"] == "12°C" and doc_c["sun"]["sunrise"] == "07:21" and doc_c["now"]["pressure"] == "1020 hPa"


def test_kp_rows_both_shapes(monkeypatch):
    from livemap_helper import sky
    monkeypatch.setattr(sky, "fetch_json", lambda *a, **k: [["time_tag", "Kp", "a_running", "station_count"], ["2026-10-26 00:00:00.000", "1.67", "6", "8"], ["2026-10-26 03:00:00.000", "2.33", "9", "8"]])
    assert sky.fetch_kp() == {"time": "2026-10-26 03:00:00.000", "kp": 2.33}
    monkeypatch.setattr(sky, "fetch_json", lambda *a, **k: [{"time_tag": "2026-10-26T03:00:00", "kp_index": 3, "estimated_kp": 2.67}])
    assert sky.fetch_kp()["kp"] == 3.0


def test_bubble_pictures_fetched_to_files(tmp_path, monkeypatch):
    """The helper fetches a bubble's picture once, hands the widget a file URL, and remembers a failure for an hour."""
    import io, urllib.request
    from livemap_helper import feed
    monkeypatch.setattr(feed, "PICTURES", tmp_path / "pictures")
    monkeypatch.setattr(feed, "PICTURES_INDEX", tmp_path / "pictures.json")
    png = b"\x89PNG\r\n\x1a\n" + b"\0" * 64
    class R:
        def __init__(self, body, ctype): self.body, self.headers = body, {"Content-Type": ctype}
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def read(self, n=-1): return self.body
    calls = []
    def fake_urlopen(req, timeout=0):
        calls.append(req.full_url)
        if "bad" in req.full_url:
            raise urllib.error.URLError("timed out")
        return R(png, "image/png")
    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)
    items = [{"image": "https://earthquake.usgs.gov/product/x/intensity.jpg"}, {"image": "https://bad.example/x.png"}, {"image": ""}]
    feed.local_pictures(items)
    assert items[0]["image"].startswith("file://") and items[0]["image"].endswith(".png")
    assert items[1]["image"].startswith("https://bad.example")           # left for the widget to try
    feed.local_pictures(items)                                             # the second run asks for nothing
    assert len(calls) == 2
    idx = json.loads((tmp_path / "pictures.json").read_text())
    assert idx["https://bad.example/x.png"]["error"].startswith("<urlopen error") or "timed out" in idx["https://bad.example/x.png"]["error"]


def test_gdacs_storm_names_keep_their_hyphen():
    import re
    from livemap_helper import storms
    assert re.sub(r"-\d{1,2}$", "", "IN-FA-25").title() == "In-Fa"
    assert re.sub(r"-\d{1,2}$", "", "VANCE-25").title() == "Vance"
    assert re.sub(r"-\d{1,2}$", "", "THREE-25").title() == "Three"
    assert "re.sub(r\"-\\d{1,2}$\"" in open(storms.__file__, encoding="utf-8").read()


def test_storm_twins_and_lenient_names():
    """Two sources' records of one storm: matched by a lenient name, else by a reach that grows with the age gap;
    what still does not merge is reported as a possible twin."""
    from livemap_helper import storms
    assert storms.same_name_key("IN-FA") == storms.same_name_key("In Fa") == storms.same_name_key("infa")
    gd = {"name": "In", "source": "GDACS", "lat": 14.0, "lon": 158.0, "hours": 30, "ids": ["gdacs:1"]}
    jt = {"name": "In-Fa", "source": "JTWC", "lat": 16.5, "lon": 150.5, "hours": 2, "ids": ["jtwc:wp30"]}   # ~900 km on, a day later
    assert storms.same_storm_reach(gd, jt) > 1200
    pairs = storms.twins([gd, jt])
    assert len(pairs) == 1
    far = {"name": "Other", "source": "JTWC", "lat": -20.0, "lon": 60.0, "hours": 1, "ids": ["jtwc:sh05"]}
    assert storms.twins([gd, far]) == []


# ---- maritime incidents (UKMTO) -----------------------------------------------------------------------------
def test_ukmto_incidents_parse():
    from livemap_helper import maritime
    items = maritime.parse_incidents(json.loads(fixture("ukmto_all.json")))
    assert len(items) == 41 and items[0]["when"] >= items[-1]["when"]          # newest first
    by_number = {it["number"]: it for it in items}
    a = by_number[147]                                                          # a red-pin attack on a tanker
    assert a["type"] == "Attack" and a["pin"] == "Red" and a["level"] == 3 and a["place"] == "Strait of Hormuz" and a["vessel_type"] == "tanker"
    assert by_number[144]["level"] == 2 and by_number[143]["level"] == 1 and by_number[184]["level"] == 1   # yellow attack, suspicious activity, advisory
    assert by_number[143]["vessel"] == "" and by_number[144]["vessel"] == ""   # "vessel" and "." are withheld names, not names
    assert abs(by_number[143]["lat"] - 26.4333) < 0.001 and abs(by_number[143]["lon"] - 56.4861) < 0.001
    assert time.gmtime(by_number[143]["when"])[:5] == (2026, 9, 28, 23, 0) and by_number[143]["published"] > by_number[143]["when"]
    assert "\r" not in by_number[143]["text"] and by_number[143]["text"].count("\n") == 2   # three paragraphs, joined inside
    assert all(it["kind"] == "maritime" and it["title"] and it["url"].startswith("https://") for it in items)


def test_ukmto_levels():
    from livemap_helper.maritime import maritime_level
    assert maritime_level("Hijack") == 3 and maritime_level("Kidnap", "Yellow") == 3
    assert maritime_level("Attack") == 2 and maritime_level("Attack", "Red") == 2 + 1 and maritime_level("Attempted Boarding") == 2
    assert maritime_level("Suspicious Activity", "Red") == 1 and maritime_level("Advisory") == 1 and maritime_level("Electronic Interference") == 1
    assert maritime_level("Suspicious Activity", pirate=True) == 3
    assert maritime_level("Something New") == 1


def test_ukmto_fetch_and_cache(no_network, data_dir):
    from livemap_helper import maritime
    no_network("api/ukmto/all", fixture("ukmto_all.json"))
    d = maritime.fetch_maritime()
    assert len(d["incidents"]) <= 41 and all(time.time() - it["when"] <= maritime.MARITIME_DAYS * 86400 for it in d["incidents"])
    data, stale, err = maritime.maritime_cached(15)
    assert err == "" and (data_dir / "last-maritime.json").exists()


def test_ukmto_odd_records_are_skipped():
    from livemap_helper import maritime
    items = maritime.parse_incidents([{"incidentNumber": 1, "locationLatitude": None, "locationLongitude": 50}, {"incidentNumber": 2, "locationLatitude": 12, "locationLongitude": 45, "utcDateOfIncident": "garbage"},
                                      {"incidentNumber": 3, "locationLatitude": 12, "locationLongitude": 45, "utcDateOfIncident": "2026-10-01T00:00:00Z", "incidentTypeName": None, "vesselType": None, "otherDetails": None, "crewHeld": "x"},
                                      "not a record", {"incidentNumber": 4, "locationLatitude": 95, "locationLongitude": 45, "utcDateOfIncident": "2026-10-01T00:00:00Z"}])
    assert [it["number"] for it in items] == [3] and items[0]["type"] == "Incident" and items[0]["title"] == "Incident · at sea" and items[0]["crew_held"] == 0
    assert maritime.parse_incidents({"incidents": []}) == [] and maritime.parse_incidents(None) == []
