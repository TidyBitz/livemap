"""Ukraine air raid alerts: alerts.in.ua or the public mirror."""
import json
import os
import urllib.error
import urllib.request

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .common import PKG, DATA, MAX_BODY, UA, _http, emit, last_good, stale_note


# ---------------------------------------------------------------- air raid alerts ----
# Ukraine's civil air-raid alerts by oblast, from alerts.in.ua (the volunteer API behind most alert apps; a free
# personal token from alerts.in.ua/api-request, 8-10 requests a minute allowed, this asks once a minute) or, with
# no token, a public mirror of the same data at oblast level (ubilling.net.ua, no key, air raid only). The oblast
# polygons ship with the package (Natural Earth 10m admin-1, thinned): data/ukraine-regions.json, keyed by ISO 3166-2.
ALERTS_API = "https://api.alerts.in.ua/v1/alerts/active.json"


ALERTS_MIRROR = "https://ubilling.net.ua/aerialalerts/?json=true"


ALERTS_MEMORY = DATA / "air-alerts.json"


AIR_CLEAR_MINUTES = 30                            # an ended alert stays listed as "all clear" this long


UA_REGIONS = PKG / "data" / "ukraine-regions.json"


# the oblast names the sources use (Ukrainian), by ISO 3166-2 code; matched on the stem so "м. Київ", "Київ" and
# "Київська область" all land
UA_STEMS = {"UA-43": "крим", "UA-07": "волин", "UA-05": "вінниц", "UA-12": "дніпропетров", "UA-14": "донец", "UA-18": "житомир",
            "UA-21": "закарпат", "UA-23": "запорі", "UA-26": "івано-франків", "UA-30": "київ", "UA-32": "київська", "UA-35": "кіровоград",
            "UA-09": "луган", "UA-46": "львів", "UA-48": "миколаїв", "UA-51": "одес", "UA-53": "полтав", "UA-56": "рівнен",
            "UA-40": "севастополь", "UA-59": "сум", "UA-61": "тернопіл", "UA-63": "харків", "UA-65": "херсон", "UA-68": "хмельниц",
            "UA-71": "черкас", "UA-77": "чернівец", "UA-74": "чернігів"}


ALERT_TYPES = {"air_raid": "air raid", "artillery_shelling": "artillery shelling", "urban_fights": "street fighting",
               "chemical": "chemical threat", "nuclear": "nuclear threat"}


def ua_region_code(title):
    """ISO code for an oblast title in Ukrainian ("Київська область", "м. Київ", "Автономна Республіка Крим")."""
    t = str(title or "").lower().replace("м.", "").replace("область", "").replace("автономна республіка", "").strip()
    if t.startswith("київська") or (t.startswith("київ") and "область" in str(title).lower()):
        return "UA-32"
    for code, stem in UA_STEMS.items():
        if code in ("UA-32",):
            continue
        if t.startswith(stem):
            return code
    return None


def ua_regions():
    try:
        return json.loads(UA_REGIONS.read_text(encoding="utf-8")).get("regions", [])
    except (OSError, ValueError):
        return []


def fetch_air_alerts(token=""):
    """{code: {status, types, since}} for every oblast with something active. status A (the whole oblast),
    P (part of it: a raion, hromada or city) from the API; the mirror only knows A."""
    import time
    now = time.time()
    out = {}
    if token:
        req = urllib.request.Request(ALERTS_API, headers=dict(UA, Authorization="Bearer " + token, Accept="application/json"))
        with urllib.request.urlopen(req, timeout=15) as r:
            data = json.loads(r.read(MAX_BODY))
        for a in data.get("alerts", []):
            code = ua_region_code(a.get("location_oblast") or a.get("location_title"))
            if not code:
                continue
            whole = a.get("location_type") == "oblast"
            since = None
            try:
                from datetime import datetime
                since = datetime.fromisoformat(str(a.get("started_at")).replace("Z", "+00:00")).timestamp()
            except (ValueError, TypeError):
                pass
            e = out.setdefault(code, {"status": "N", "types": [], "since": None, "places": [], "latest": None})
            if whole:
                e["status"] = "A"
            elif e["status"] != "A":
                e["status"] = "P"
                if a.get("location_title") and len(e["places"]) < 4:
                    e["places"].append(a.get("location_title_en") or a.get("location_title"))
            t = ALERT_TYPES.get(a.get("alert_type") or "", a.get("alert_type") or "")
            if t and t not in e["types"]:
                e["types"].append(t)
            if since and (e["since"] is None or since < e["since"]):
                e["since"] = since
            if since and (e["latest"] is None or since > e["latest"]):
                e["latest"] = since                           # the newest alert inside the oblast: a raion or city joining
        source = "alerts.in.ua"
    else:
        data = json.loads(_http(ALERTS_MIRROR, timeout=15)[2])
        for title, st in (data.get("states") or {}).items():
            if not (st or {}).get("alertnow"):
                continue
            code = ua_region_code(title)
            if code:
                out[code] = {"status": "A", "types": ["air raid"], "since": None, "places": [], "latest": None}
        source = "mirror"
    # Our own memory of when each alert started, for the mirror (which does not say). A start is only known when
    # this helper saw the oblast go from quiet to alert; an alert already on at the first look has no known start,
    # and is reported with since = null rather than a made-up time. The memory also says when the last look was,
    # so a gap in watching (the machine asleep) resets what counts as "seen begin".
    try:
        mem = json.loads(ALERTS_MEMORY.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        mem = {}
    watching = now - float(mem.get("_at", 0)) < 600          # looked within the last ten minutes: a new alert is a seen start
    for code, e in out.items():
        m = mem.get(code)
        if e["since"] is not None:
            mem[code] = {"since": e["since"], "known": True, "first_seen": (m or {}).get("first_seen", now) if isinstance(m, dict) else now}
        elif isinstance(m, dict):
            e["since"] = m["since"] if m.get("known") else None
            m.setdefault("first_seen", m["since"])
        else:
            mem[code] = {"since": now, "known": watching, "first_seen": now}
            e["since"] = now if watching else None
        e["first_seen"] = mem[code].get("first_seen", now)
        # renewed: something new inside an oblast already under alert - a raion or city joining (its own, later
        # start) or an alert type added (shelling on top of the air raid). Only the API tells; the mirror never
        # renews. The oblast then counts as fresh again, which is what lets a long-running one resurface.
        prev_types = mem[code].get("types") or []
        added = [t for t in e.get("types") or [] if t not in prev_types]
        renewed = mem[code].get("renewed")
        latest = e.get("latest")
        if latest and e["since"] and latest > e["since"] + 60 and latest > (renewed or 0):
            renewed = latest
        if added and prev_types and watching:
            renewed = max(renewed or 0, now)
        mem[code]["types"] = list(e.get("types") or [])
        if renewed:
            mem[code]["renewed"] = renewed
        e["renewed"] = renewed
    # alerts that ended: kept for AIR_CLEAR_MINUTES as "all clear", so the map can show where one just finished
    cleared = mem.setdefault("_cleared", {})
    for code in list(mem):
        if code.startswith("_") or code in out:
            continue
        cleared[code] = {"ended": now, "since": mem[code].get("since") if mem[code].get("known") else None}
        del mem[code]
    for code in list(cleared):
        if code in out or now - cleared[code]["ended"] > AIR_CLEAR_MINUTES * 60:
            del cleared[code]
    for code, c in cleared.items():
        out[code] = {"status": "C", "types": [], "since": c.get("since"), "places": [], "ended": c["ended"], "first_seen": None}
    mem["_at"] = now
    try:
        ALERTS_MEMORY.parent.mkdir(parents=True, exist_ok=True)
        ALERTS_MEMORY.write_text(json.dumps(mem), encoding="utf-8")
    except OSError:
        pass
    return {"alerts": out, "source": source, "at": now}


def cmd_air_alerts(args):
    """`air-alerts [--token T] [--table]`: the oblasts under alert, with the regions' polygons on request (`--regions`)."""
    import time
    token = args.token or os.environ.get("LIVEMAP_ALERTS_TOKEN", "")
    data, stale_h, err = last_good("air-alerts", lambda: fetch_air_alerts(token))
    note = ""
    if err:
        note = stale_note("Air raid alerts", stale_h, err, args.stale)
    alerts = (data or {}).get("alerts", {})
    regions = ua_regions()
    rows = []
    for r in regions:
        e = alerts.get(r["code"])
        row = {"code": r["code"], "name": r["name"], "lat": r["lat"], "lon": r["lon"],
               "status": e["status"] if e else "N", "types": e["types"] if e else [], "since": e["since"] if e else None, "places": e["places"] if e else [],
               "first_seen": e.get("first_seen") if e else None, "ended": e.get("ended") if e else None}
        if args.regions:
            row["rings"] = r["rings"]
        rows.append(row)
    if args.table:
        print(note or "%d oblasts under alert (%s)" % (sum(1 for a in alerts.values() if a["status"] != "N"), (data or {}).get("source", "?")))
        for row in rows:
            if row["status"] == "N":
                continue
            print("  %-6s %-28s %s  %s  %s%s" % (row["code"], row["name"], row["status"], ", ".join(row["types"]) or ("all clear %.0f min ago" % ((time.time() - row["ended"]) / 60) if row.get("ended") else ""),
                                                 "%.0f min" % ((time.time() - row["since"]) / 60) if row["since"] else "",
                                                 "  (" + ", ".join(row["places"]) + ")" if row["places"] else ""))
    else:
        emit({"regions": rows, "source": (data or {}).get("source", ""), "note": note, "stale_hours": stale_h})


def chk_air_alerts():
    token = os.environ.get("LIVEMAP_ALERTS_TOKEN", "")
    d = fetch_air_alerts(token)
    on = [c for c, a in d["alerts"].items() if a["status"] in ("A", "P")]
    names = {r["code"]: r["name"] for r in ua_regions()}
    return "ok", "%d of 27 oblasts under alert (%s%s)%s" % (len(on), d["source"], "" if token else ": no token, oblast level only",
                                                             ": " + ", ".join(names.get(c, c) for c in on[:8]) if on else "")
