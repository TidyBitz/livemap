"""The Events widget's list: every layer's events, history, the newest-first bookkeeping."""
import json
import os
import urllib.error
import urllib.request

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .alerts import fetch_air_alerts, ua_regions
from .common import DATA, EVENTS, HISTORY, HISTORY_DAYS, VERSION, _age, area_text, emit, last_good, \
    on_battery, read_fire_focus, read_fire_sources, read_flood_level, read_layers, read_layers_flag, read_layers_int, read_units, \
    wind_text
from .fires import INCIDENT_SOURCES, cluster_hotspots, fetch_fires, fetch_hotspots, hotspot_source, incidents_cached, \
    rate_hotspots
from .quakes import quakes_cached
from .floods import official_floods, group_nws, people_text
from .infra import impact_text
from .power import cpu_busy, gpu_busy
from .space import SATS, fetch_launches
from .tsunami import tsunami_cached


# ------------------------------------------------------------------ feed -----
def cmd_feed(args):
    """The newest events across every source, with a link each, for the companion widget. Everything comes
    from the caches the wallpaper already keeps, plus one small USGS request (cached 5 min)."""
    import time
    now, items, problems = time.time(), [], []
    # earthquakes (the merged USGS + EMSC list the layer reads; cached 5 min)
    try:
        qfeatures, qproblems = quakes_cached(args.feed, read_layers_int("quake_sources", 3))
        problems += qproblems
        for f in qfeatures:
            p, c = f.get("properties") or {}, (f.get("geometry") or {}).get("coordinates") or [0, 0]
            items.append({"kind": "quake", "when": p.get("time", 0) / 1000, "title": "M%.1f \u00b7 %s" % (p.get("mag") or 0, p.get("place") or ""),
                          "detail": p.get("source") or "USGS", "url": p.get("url") or "", "lat": c[1], "lon": c[0], "level": 3 if (p.get("mag") or 0) >= 6 else 2 if (p.get("mag") or 0) >= 5 else 1,
                          "key": "quake:%s" % (f.get("id") or p.get("code") or "%s,%s" % (c[0], c[1]))})
    except Exception as e:
        problems.append("quakes: %s" % e)
    # remembered events: storms, volcanoes, fires (first seen / changed)
    try:
        mem = json.loads(EVENTS.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        mem = {}
    units = read_units()                            # the wallpaper's Units and Storm wind choices
    fire_focus = read_fire_focus()                  # and its Wildfire focus
    flood_level = read_flood_level()                # and its flood filter
    for kind, url_of, title_of in (
            ("storm", lambda it: "https://www.gdacs.org/report.aspx?eventid=%s&eventtype=TC" % it.get("id", ""),
             lambda it: "%s \u00b7 %s%s \u00b7 %s%s%s" % (it.get("name", "?"), it.get("kind", ""), " cat %d" % it["cat"] if it.get("cat") else "", wind_text(float(it.get("wind") or 0), units[1]),
                                                           " \u00b7 was %s" % str(it["was_named"]).title() if it.get("was_named") else "",
                                                           " \u00b7 " + impact_text(it["impact"]) if it.get("impact") else "")),
            ("volcano", lambda it: "https://volcano.si.edu/search_volcano.cfm?keyword=%s" % urllib.request.quote(it.get("name", "")),
             lambda it: "%s \u00b7 %s%s" % (it.get("name", "?"), (it.get("level") + " (" + it.get("alert", "") + ")") if it.get("alert") else "new eruption" if it.get("status") == "new" else "active",
                                            " \u00b7 ash to FL%s" % it["ash_top_fl"] if it.get("ash_top_fl") else " \u00b7 ash advisory" if it.get("ash_hours") is not None else "")),
            ("fire", lambda it: "https://www.gdacs.org/report.aspx?eventid=%s&eventtype=WF" % it.get("id", ""),
             lambda it: "%s \u00b7 %s \u00b7 %s" % (it.get("name", "?"), it.get("alert", ""), area_text(float(it.get("area_ha") or 0), units[0]))),
            ("flood", lambda it: "https://www.gdacs.org/report.aspx?eventid=%s&eventtype=FL" % it.get("id", ""),
             lambda it: "%s \u00b7 %s flood%s" % (it.get("name", "?"), it.get("alert", ""), " \u00b7 " + people_text(it["people"]) if it.get("people") else ""))):
        for key, e in (mem.get(kind) or {}).items():
            it = e.get("item") or {}
            if not it:
                continue
            when = e.get("changed") or e.get("first")
            if when is None:
                continue
            title = title_of(it) + (" \u00b7 was %s" % e.get("was") if e.get("changed") and e.get("was") else " \u00b7 new")
            ev = {"kind": kind, "when": when, "title": title, "detail": "GDACS" if kind != "volcano" else ("Smithsonian / " + ({"GeoNet": "GeoNet", "JMA": "JMA"}.get(it.get("observatory"), "USGS")) + (" / VAAC" if it.get("ash_hours") is not None else "")),
                  "url": url_of(it), "lat": it.get("lat"), "lon": it.get("lon"), "key": "%s:%s:%s" % (kind, key, int(when)),
                  "level": 3 if it.get("alert") in ("red",) or it.get("cat", 0) >= 3 else 2 if it.get("alert") == "orange" or it.get("cat", 0) >= 1 or it.get("status") == "new" else 1}
            if kind == "fire" and fire_focus >= 1 and it.get("alert") not in ("orange", "red"):
                continue                                   # Wildfire focus: only the events GDACS rates on the people exposed
            if kind == "flood" and ["green", "orange", "red"].index(it.get("alert") or "green") < flood_level:
                continue                                   # the wallpaper's flood filter (green floods are a basin's seasonal high water)
            if kind == "storm" and it.get("impact"):   # the facilities it crossed and those in its path, for the widget
                ev["facilities"] = {"crossed": it["impact"].get("crossed") or [], "ahead": it["impact"].get("ahead") or []}
            items.append(ev)
    # named fire incidents (NIFC, CWFIS, EFFIS: the sources the wallpaper has on; cached half an hour)
    try:
        bits = read_fire_sources()
        for src, bit in (("nifc", 4), ("cwfis", 8), ("effis", 16)):
            if not (bits & bit):
                continue
            data, _h, _e = incidents_cached(src, 30)
            for it in data or []:
                active = it.get("stage") in ("out of control", "being held") or (it.get("contained") is not None and it["contained"] < 100) or (src == "effis" and (it.get("days") or 99) < 7)
                big = it["area_ha"] >= 1000 or it.get("personnel", 0) >= 100 or it.get("stage") == "out of control"
                if fire_focus > 0 and not big:
                    continue
                parts = [it["name"], area_text(float(it["area_ha"]), units[0])]
                if it.get("contained") is not None:
                    parts.append("%d %% contained" % it["contained"])
                elif it.get("stage"):
                    parts.append(it["stage"])
                if it.get("personnel"):
                    parts.append("%d personnel" % it["personnel"])
                items.append({"kind": "fire", "when": now - (it.get("hours") or 0) * 3600, "title": " \u00b7 ".join(parts),
                              "detail": "%s%s" % (src.upper(), " \u00b7 " + it["region"] if it.get("region") else ""), "url": it.get("url", ""),
                              "lat": it["lat"], "lon": it["lon"], "key": it["id"],
                              "level": 3 if active and it["area_ha"] >= 10000 else 2 if active and big else 1})
    except Exception as e:
        problems.append("incidents: %s" % e)
    # air raid alerts: the wallpaper's minute-by-minute cache when fresh (it carries the token's detail), else the mirror
    try:
        f = DATA / "last-air-alerts.json"
        aa = None
        try:
            c = json.loads(f.read_text(encoding="utf-8"))
            if now - c.get("at", 0) < 180:
                aa = c["data"]
        except (OSError, ValueError, KeyError):
            pass
        if aa is None:
            aa, _h, _e = last_good("air-alerts", lambda: fetch_air_alerts(""))
        names = {r["code"]: r for r in ua_regions()}
        for code, a in ((aa or {}).get("alerts") or {}).items():
            r = names.get(code)
            if not r or a.get("status") == "N":
                continue
            if a.get("status") == "C":
                items.append({"kind": "alert", "when": a.get("ended") or now, "title": "All clear \u00b7 %s" % r["name"], "detail": "the alert ended" + (" after " + _age((a.get("ended") or now) - a["since"]) if a.get("since") else ""),
                              "url": "https://alerts.in.ua/en", "lat": r["lat"], "lon": r["lon"], "level": 1, "nonew": True, "key": "clear:%s:%d" % (code, int(a.get("ended") or now))})
                continue
            kinds = a.get("types") or ["air raid"]
            severe = any(k != "air raid" for k in kinds)
            items.append({"kind": "alert", "when": a.get("since") or now, "title": "%s \u00b7 %s%s" % (", ".join(kinds).capitalize(), r["name"], " (part)" if a.get("status") == "P" else ""),
                          "detail": ("alerts.in.ua" if (aa or {}).get("source") != "mirror" else "mirror, oblast level") + (" \u00b7 " + ", ".join(a["places"]) if a.get("places") else "") + ("" if a.get("since") else " \u00b7 on since before the first look"),
                          "nonew": not a.get("since"), "url": "https://alerts.in.ua/en",
                          "lat": r["lat"], "lon": r["lon"], "level": 3 if severe else 2, "key": "alert:%s:%d" % (code, int(a.get("since") or now))})
    except Exception as e:
        problems.append("air alerts: %s" % e)
    # NWS flood alerts (the wallpaper's cache; fetched when it is more than 10 minutes old)
    try:
        nws, _note = official_floods(read_layers_int("flood_sources", 15), 10)
        if not read_layers_flag("nws_each"):
            nws = group_nws(nws or [])
        for a in nws or []:
            if ["green", "orange", "red"].index(a["alert"]) < flood_level:
                continue
            items.append({"kind": "flood", "when": a.get("onset") or now, "title": "%s \u00b7 %s" % (a["event"], a["name"]),
                          "detail": "%s%s%s" % ({"meteoalarm": "MeteoAlarm", "eccc": "Environment Canada", "ea": "Environment Agency"}.get(a.get("source"), "NWS"), "" if a.get("count") or a.get("source") not in (None, "nws") else " " + a["office"],
                                                 " \u00b7 until " + time.strftime("%a %H:%M", time.localtime(a["until"])) if a.get("until") else ""),
                          "url": a["url"], "lat": a["lat"], "lon": a["lon"], "level": 3 if a["alert"] == "red" else 2 if a["alert"] == "orange" else 1, "key": a["id"]})
    except Exception as e:
        problems.append("nws floods: %s" % e)
    # tsunami bulletins (the wallpaper's cache; fetched when it is more than 5 minutes old)
    try:
        ts, _h, _e = tsunami_cached(5)
        for e in (ts or {}).get("events", []):
            what = ("Threat ended" if e.get("ended") else e["event"].replace("Message", "").strip()) if e["level"] > 0 or e.get("ended") else "Tsunami evaluated, no threat"
            items.append({"kind": "tsunami", "when": e["sent"], "title": "%s · %s%s" % (what, "M%.1f " % e["mag"] if e.get("mag") else "", e.get("location") or ""),
                          "detail": "%s · %s" % (e["centre"], (", ".join(e["areas"][:4]) + (", +%d" % (len(e["areas"]) - 4) if len(e["areas"]) > 4 else "")) if e.get("areas") else ("bulletin %s" % (e.get("severity") or "").lower() if e["level"] <= 0 else e["event"])),
                          "url": e["url"], "lat": e["lat"], "lon": e["lon"], "level": 3 if e["level"] >= 2 and e["active"] else 2 if e["level"] > 0 and e["active"] else 1,
                          "nonew": e["level"] <= 0 and not e.get("ended"), "key": "tsunami:%s:%s" % (e["centre"], e["incident"])})
    except Exception as e:
        problems.append("tsunami: %s" % e)
    # satellite fire clusters that need attention (the helper's rating; the wallpaper's cache, nothing extra fetched when fresh)
    try:
        fires_now, _h, _e = last_good("fires", fetch_fires)
        for c in rate_hotspots(cluster_hotspots(fetch_hotspots()), fires_now or []) if fire_focus < 2 else []:
            if c["tier"] < 2 or (fire_focus == 1 and not c.get("people")):
                continue
            items.append({"kind": "fire", "when": now - c["hours"] * 3600, "title": "Fire hotspots \u00b7 %s \u00b7 %s" % (c["why"], "%.1f GW" % (c["frp"] / 1000) if c["frp"] >= 1000 else "%d MW" % c["frp"]),
                          "detail": "NASA FIRMS %s \u00b7 %d detections" % (hotspot_source(), c.get("raw", c["n"])), "url": "https://firms.modaps.eosdis.nasa.gov/map/#d:24hrs;@%.2f,%.2f,7z" % (c["lon"], c["lat"]),
                          "lat": c["lat"], "lon": c["lon"], "level": 2, "key": "hot:%d,%d" % (int(c["lat"] // 0.5), int(c["lon"] // 0.5))})
    except Exception as e:
        problems.append("hotspots: %s" % e)
    # launches
    try:
        for L in fetch_launches():
            if now - 1800 < L["net"] < now + 7 * 86400:
                items.append({"kind": "launch", "when": L["net"], "title": "%s \u00b7 %s" % (L["rocket"], L["mission"] or L["name"]),
                              "detail": "%s \u00b7 %s" % (L["provider"], L["site"]), "url": (L.get("videos") or [{}])[0].get("url") or "https://ll.thespacedevs.com/2.2.0/launch/%s/" % L["id"],
                              "lat": L["lat"], "lon": L["lon"], "level": 3 if L["net"] - now < 900 else 2 if L["net"] - now < 3600 else 1, "future": True,
                              "videos": L.get("videos") or [], "webcast_live": L.get("webcast_live", False), "status": L.get("status", ""),
                              "key": "launch:%s" % L["id"]})
    except Exception as e:
        problems.append("launches: %s" % e)
    # satellites
    try:
        for short, catnr, longname in SATS:
            it = {"kind": "sat", "when": now, "title": longname, "detail": "live position on the map",
                  "url": "https://www.n2yo.com/satellite/?s=%s" % catnr, "lat": None, "lon": None, "level": 0, "pin": True, "links": []}
            if short == "ISS":                            # the people on board, and the station's own news
                it["links"] = [{"label": "Who is in space right now", "icon": "user-group-new", "url": "https://issinfo.net/whos-in-space"}]
            elif short == "Tiangong":
                it["links"] = [{"label": "Who is in space right now", "icon": "user-group-new", "url": "https://issinfo.net/whos-in-space"}]
            items.append(it)
    except Exception:
        pass
    remember_history(items, now)
    if args.since is not None or args.until is not None:          # the past: from the history file, not the live feeds
        since, until = args.since if args.since is not None else 0, args.until if args.until is not None else now + 1
        past = [it for it in read_history().values() if since <= it["when"] <= until]
        for it in past:
            it["past"] = True
            if it.get("future") and it["when"] < now:
                it["future"] = False                                  # a launch that has happened since
        past.sort(key=lambda it: -it["when"])
        emit({"items": past[:args.limit], "problems": problems, "version": VERSION, "history_days": HISTORY_DAYS,
              "history_from": min((it["when"] for it in read_history().values()), default=None)})
        return
    items.sort(key=lambda it: (1 if it.get("pin") else 0, -it["when"]))
    # The cap is for the long tails (a day of quakes, dozens of fire clusters): a storm first seen three days
    # ago is still on the map and must not fall off the end of the list because of them.
    # Floods and named fire incidents are long-lived too (a fire's last update can be days old, so by time it
    # sorts behind every quake of the day); they are already filtered to the ones that matter.
    def kept(it):
        return it["kind"] in ("storm", "volcano", "launch", "sat", "flood", "alert", "tsunami") or str(it.get("key", "")).split(":")[0] in INCIDENT_SOURCES
    # the kept kinds are exempt from the cap, not counted against it: 60 fire incidents must not push out every quake
    keep = [it for it in items if kept(it)]
    rest = [it for it in items if not kept(it)][:max(0, args.limit)]
    items = sorted(keep + rest, key=lambda it: (1 if it.get("pin") else 0, -(it.get("updated") or it["when"])))
    emit({"items": items, "problems": problems, "version": VERSION, "layers": read_layers(), "ages": data_ages(now)})


HISTORY_MARK = 2                                                  # the seen/updated bookkeeping's version


def history_mark():
    try:
        h = json.loads(HISTORY.read_text(encoding="utf-8"))
        return h.get("news") if isinstance(h, dict) else None
    except (OSError, ValueError):
        return None


# the cache file(s) behind each kind of event: "as of" for the widget, so an empty list can say whether the
# source was reached (the kind's newest cache) or never answered (no cache at all)
KIND_CACHES = {"quake": ["quakes.json"], "storm": ["last-storms.json"], "volcano": ["last-volcanoes.json"], "fire": ["last-fires.json", "hotspots.csv", "last-nifc.json", "last-cwfis.json", "last-effis.json"],
               "flood": ["last-floods.json", "last-nws-floods.json"], "tsunami": ["last-tsunami.json"], "alert": ["last-air-alerts.json"],
               "launch": ["launches.json"], "sat": ["tle.json"]}


def data_ages(now):
    """{kind: minutes since its freshest cache was written}; a kind with no cache is left out."""
    out = {}
    for kind, files in KIND_CACHES.items():
        ages = []
        for f in files:
            try:
                ages.append((now - (DATA / f).stat().st_mtime) / 60)
            except OSError:
                pass
        if ages:
            out[kind] = round(min(ages), 1)
    return out


def read_history():
    try:
        h = json.loads(HISTORY.read_text(encoding="utf-8"))
        return h.get("items", {}) if isinstance(h, dict) else {}
    except (OSError, ValueError):
        return {}


def remember_history(items, now):
    """Every event the feed shows is kept by key (a launch is updated until it has flown, so its final time and
    status win); entries older than HISTORY_DAYS go. Nothing is fetched for this: it is a side effect of `feed`."""
    hist = read_history()
    changed = False
    reseed = history_mark() != HISTORY_MARK                       # the first look with this news bookkeeping (or a
                                                                  # fix to it): every entry's clock is set afresh
    def seed(old):                                                # an entry from before seen/updated were kept:
        when = old.get("when") or now                             # a past event was news when it happened; a planned
        return when if when <= now else now - 86400               # one is at least a day old, never today's news
    for it in items:
        key = it.get("key")
        if not key or it.get("pin"):
            if it.get("pin"):
                it["seen"] = it["updated"] = 0                        # a satellite is never news: it sorts last
            else:
                it["seen"] = it["updated"] = it.get("when") or now
            continue
        keep = {k: v for k, v in it.items() if k not in ("videos", "webcast_live", "pin", "links", "seen", "updated")}
        old = hist.get(key)
        was = {k: v for k, v in old.items() if k not in ("seen", "updated")} if old else None
        # "seen": when this computer first saw the event; "updated": when it last changed (a launch slipping or
        # entering its last hour, a storm's category, a volcano's level): the widget's "newest first" order
        if was != keep and (old is None or it.get("future") or was.get("when") != keep["when"] or was.get("title") != keep["title"]
                            or was.get("level") != keep.get("level") or was.get("facilities") != keep.get("facilities")):
            keep["seen"] = (old.get("seen") or seed(old)) if old else now
            keep["updated"] = now if (old is None or was.get("when") != keep["when"] or was.get("title") != keep["title"]
                                      or was.get("level") != keep.get("level")) else old.get("updated", now)
            hist[key] = keep
            changed = True
        elif old:
            old.setdefault("seen", seed(old)); old.setdefault("updated", old["seen"])   # entries from before 0.48
        if reseed and old is not None:
            hist[key]["seen"] = hist[key]["updated"] = seed(hist[key])
        it["seen"], it["updated"] = hist[key].get("seen", now), hist[key].get("updated", now)
    cutoff = now - HISTORY_DAYS * 86400
    stale = [k for k, v in hist.items() if (v.get("when") or 0) < cutoff]
    for k in stale:
        hist.pop(k, None)
    if changed or stale or reseed:
        try:
            HISTORY.parent.mkdir(parents=True, exist_ok=True)
            tmp = HISTORY.with_suffix(".tmp%d" % os.getpid())
            tmp.write_text(json.dumps({"items": hist, "news": HISTORY_MARK}, separators=(",", ":")), encoding="utf-8")
            tmp.replace(HISTORY)
        except OSError:
            pass


def chk_power():
    cpu, (gpu, how) = cpu_busy(), gpu_busy()
    return "ok", "%s; CPU %s, GPU %s (%s)" % ("on battery" if on_battery() else "on mains power",
                                              "%d %%" % cpu if cpu is not None else "n/a", "%d %%" % gpu if gpu is not None else "n/a",
                                              {"amd": "sysfs", "nvidia": "nvidia-smi", "intel-clock": "Intel clock estimate", "none": "no reading, CPU decides"}[how])
