"""Tsunami bulletins: tsunami.gov (PTWC, NTWC), remembered by event."""
import json
import os

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .common import DATA, _age, _http, emit, last_good, safe_xml, stale_note, fetch_json


# -------------------------------------------------------------- tsunami -----
# Tsunami bulletins from the two US centres that watch the world's oceans: the Pacific Tsunami Warning Center
# (PTWC: the Pacific, the Caribbean, and threat messages for the Indian Ocean and the rest of the world) and the
# National Tsunami Warning Center (NTWC: the US and Canadian coasts). tsunami.gov publishes each centre's latest
# message as one CAP 1.2 file - one file, one message, overwritten by the next product of any kind (an
# information statement two hours later replaces a threat message), so this is not a feed to read as a list:
# every message is remembered here by event, and a threat stays on the map until it expires or a later message
# for the same event stands it down. Public domain (US government).
TSUNAMI_CAP = [("PTWC", "https://www.tsunami.gov/events/xml/PHEBCAP.xml"), ("NTWC", "https://www.tsunami.gov/events/xml/PAAQCAP.xml")]


TSUNAMI_STATE = DATA / "tsunami.json"


# the message's event name -> level: 0 an evaluation with no threat, 1 watch, 2 advisory, 3 warning / threat
TSUNAMI_LEVELS = (("warning", 3), ("threat", 3), ("advisory", 2), ("watch", 1), ("information", 0), ("cancel", -1))


TSUNAMI_KEEP_HOURS = {0: 6, 1: 24, 2: 24, 3: 24, -1: 3}                  # how long a message stays, past its own expiry


TSUNAMI_HOURS = 36                                                         # events older than this leave the memory


def tsunami_level(event):
    e = (event or "").lower()
    for word, level in TSUNAMI_LEVELS:
        if word in e:
            return level
    return 0


def parse_tsunami_cap(xml_text, centre):
    """One tsunami.gov CAP message -> a record, or None when it is not a tsunami product."""
    import xml.etree.ElementTree as ET
    from datetime import datetime, timezone
    root = ET.fromstring(safe_xml(xml_text))
    local = lambda el: el.tag.rsplit("}", 1)[-1]
    text = {}
    params = {}
    area, circle = "", None
    for el in root.iter():
        name = local(el)
        if name in ("identifier", "sent", "status", "msgType", "incidents", "event", "severity", "urgency", "certainty",
                    "onset", "expires", "headline", "description", "instruction", "web") and name not in text:
            text[name] = (el.text or "").strip()
        elif name == "parameter":
            k = v = ""
            for c in el:
                if local(c) == "valueName":
                    k = (c.text or "").strip()
                elif local(c) == "value":
                    v = (c.text or "").strip()
            if k:
                params[k] = v
        elif name == "areaDesc" and not area:
            area = (el.text or "").strip()
        elif name == "circle" and circle is None:
            circle = (el.text or "").strip()
        elif name == "uri" and (el.text or "").endswith(".json"):
            text.setdefault("json", (el.text or "").strip())
    if text.get("status", "Actual") != "Actual" or "tsunami" not in (text.get("event", "") + " " + text.get("headline", "")).lower():
        return None

    def epoch(t):
        try:
            return datetime.strptime(t[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc).timestamp()
        except (ValueError, TypeError):
            return None
    lat = lon = None
    ll = params.get("EventLatLon") or (circle or "").split(" ")[0]
    try:
        lat, lon = (float(x) for x in ll.replace(" ", ",").split(",")[:2])
    except (ValueError, TypeError):
        pass
    try:
        mag = float(params.get("EventPreliminaryMagnitude") or 0) or None
    except ValueError:
        mag = None
    level = tsunami_level(text.get("event"))
    if text.get("msgType") == "Cancel":
        level = -1
    desc = " ".join(text.get("description", "").split())
    return {"id": text.get("identifier", ""), "centre": centre, "incident": text.get("incidents") or text.get("identifier", "").rsplit("-", 1)[-1],
            "event": text.get("event", "Tsunami"), "level": level, "severity": text.get("severity", ""), "sent": epoch(text.get("sent", "")),
            "expires": epoch(text.get("expires", "")), "mag": mag, "magtype": params.get("EventPreliminaryMagnitudeType", ""),
            "origin": epoch(params.get("EventOriginTime", "")), "lat": lat, "lon": lon, "depth": params.get("EventDepth", ""),
            "location": (params.get("EventLocationName") or area or "").title(), "area": area, "headline": " ".join(text.get("headline", "").split()),
            "description": desc[:600], "url": text.get("web", "").replace("http://", "https://") or "https://www.tsunami.gov/", "json": text.get("json", "")}


def tsunami_segments(json_url):
    """The threatened coast from the bulletin's own JSON: [[name, lat, lon, lat2, lon2, category], ...] from the
    breakpoint segments, and the named areas. Empty for an information statement."""
    try:
        d = fetch_json(json_url.replace("http://", "https://"), timeout=12)
    except Exception:
        return [], []
    segs, areas = [], []
    for sg in d.get("segments") or []:
        try:
            cat = str(sg.get("category") or "")
            if tsunami_level(cat) <= 0:
                continue
            segs.append([str(sg.get("bkp_start_location") or ""), float(sg["bkp_start_lat"]), float(sg["bkp_start_lon"]),
                         float(sg["bkp_end_lat"]), float(sg["bkp_end_lon"]), cat])
        except (KeyError, TypeError, ValueError):
            continue
    for lst in (d.get("alerts") or {}).get("areaList") or []:
        for a in (lst if isinstance(lst, list) else [lst]):
            if isinstance(a, str) and a.strip():
                areas.append(a.strip().title())
            elif isinstance(a, dict):
                areas.append(str(a.get("name") or a.get("area") or "").title())
    return segs, [a for a in areas if a]


def fetch_tsunami():
    """Read both centres' latest messages and fold them into the memory; return the live events."""
    import time
    now = time.time()
    try:
        state = json.loads(TSUNAMI_STATE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        state = {}
    events = state.get("events") or {}
    failed = []
    for centre, url in TSUNAMI_CAP:
        try:
            rec = parse_tsunami_cap(_http(url, timeout=15)[2].decode("utf-8", "replace"), centre)
        except Exception as e:
            failed.append("%s - %s" % (centre, e))
            continue
        if rec is None or not rec.get("sent"):
            continue
        key = "%s:%s" % (centre, rec["incident"])
        old = events.get(key)
        if old and old.get("id") == rec["id"]:
            continue                                              # the same message as last time
        if old and (old.get("sent") or 0) > rec["sent"]:
            continue
        rec["first_seen"] = old.get("first_seen", now) if old else now
        rec["peak"] = max(rec["level"], old.get("peak", 0) if old else 0)
        if old and old.get("level", 0) > 0 and rec["level"] <= 0:
            rec["ended"] = now                                    # a threat stood down by an information statement or a cancellation
        elif old and old.get("ended"):
            rec["ended"] = old["ended"] if rec["level"] <= 0 else None
        rec["segments"], rec["areas"] = tsunami_segments(rec["json"]) if rec["level"] > 0 and rec.get("json") else ([], [])
        events[key] = rec
    cutoff = now - TSUNAMI_HOURS * 3600
    latest = max(list(events.values()) + [state.get("latest") or {}], key=lambda v: v.get("sent") or 0, default=None)
    latest = {k: latest[k] for k in ("centre", "event", "mag", "location", "sent", "level") if latest and k in latest} if latest and latest.get("sent") else None
    events = {k: v for k, v in events.items() if (v.get("sent") or 0) >= cutoff}
    try:
        TSUNAMI_STATE.parent.mkdir(parents=True, exist_ok=True)
        tmp = TSUNAMI_STATE.with_suffix(".tmp%d" % os.getpid())
        tmp.write_text(json.dumps({"events": events, "latest": latest, "read": now}, separators=(",", ":")), encoding="utf-8")
        tmp.replace(TSUNAMI_STATE)
    except OSError:
        pass
    if failed and len(failed) == len(TSUNAMI_CAP):
        raise RuntimeError("; ".join(failed))
    out = []
    for v in events.values():
        keep = TSUNAMI_KEEP_HOURS.get(v.get("level", 0), 6) * 3600
        until = max(v.get("expires") or 0, (v.get("sent") or 0) + keep)
        if until < now:
            continue
        it = dict(v)
        it["hours"] = round((now - v["sent"]) / 3600, 2)
        it["first_hours"] = round((now - v.get("first_seen", v["sent"])) / 3600, 2)
        it["active"] = v.get("level", 0) > 0 and not v.get("ended") and (v.get("expires") or now + 1) > now
        out.append(it)
    out = merge_twins(out)
    out.sort(key=lambda it: (-(it["level"] if it["active"] else -1), -it["sent"]))
    return {"events": out, "problems": failed, "latest": latest}


def merge_twins(events):
    """PTWC and NTWC each issue a message for the same quake (one for the Pacific, one for the US and Canadian
    coasts). Two messages about the same earthquake - the same magnitude within 0.2, within 1.5 degrees and
    half an hour of each other - become one event: the higher level, both centres named, every area, the
    lists of segments joined."""
    out = []
    for e in events:
        twin = None
        for o in out:
            try:
                same = (abs(float(o.get("mag") or 0) - float(e.get("mag") or 0)) <= 0.2 and abs(o["lat"] - e["lat"]) <= 1.5
                        and abs(o["lon"] - e["lon"]) <= 1.5 and abs(o["sent"] - e["sent"]) <= 1800 and o.get("centre") != e.get("centre"))
            except (TypeError, KeyError):
                same = False
            if same:
                twin = o
                break
        if twin is None:
            out.append(dict(e))
            continue
        lead, other = (twin, e) if (twin["level"], twin["sent"]) >= (e["level"], e["sent"]) else (e, twin)
        merged = dict(lead)
        merged["centre"] = "%s \u00b7 %s" % (lead["centre"], other["centre"])
        merged["centres"] = sorted({lead["centre"], other["centre"]})
        merged["areas"] = list(dict.fromkeys((lead.get("areas") or []) + (other.get("areas") or [])))
        merged["segments"] = (lead.get("segments") or []) + (other.get("segments") or [])
        merged["active"] = lead["active"] or other["active"]
        merged["twin_url"] = other.get("url", "")
        out[out.index(twin)] = merged
    return out


def tsunami_cached(max_age_min=5):
    import time
    f = DATA / "last-tsunami.json"
    try:
        c = json.loads(f.read_text(encoding="utf-8"))
        if time.time() - c.get("at", 0) < max_age_min * 60:
            return c["data"], 0.0, ""
    except (OSError, ValueError, KeyError):
        pass
    return last_good("tsunami", fetch_tsunami)


def cmd_tsunami(args):
    data, stale_h, err = tsunami_cached(args.max_age)
    note = stale_note("Tsunami bulletins", stale_h, err, args.stale) if err else ""
    events = (data or {}).get("events", [])
    if args.table:
        print(note or "%d tsunami bulletins remembered, %d threats active" % (len(events), sum(1 for e in events if e["active"])))
        for e in events:
            print("  %-5s %-22s L%d %-6s M%s %-28s %s  %s%s" % (e["centre"], e["event"][:22], e["level"], "active" if e["active"] else ("ended" if e.get("ended") else "info"),
                                                             e.get("mag") or "?", e.get("location", "")[:28], "%.1f h ago" % e["hours"],
                                                             "%d coast segments" % len(e.get("segments") or []), ", " + ", ".join(e.get("areas") or [])[:60] if e.get("areas") else ""))
    else:
        emit({"events": events, "note": note, "problems": (data or {}).get("problems", [])})


def chk_tsunami():
    import time
    d = fetch_tsunami()
    act = [e for e in d["events"] if e["active"]]
    latest = d.get("latest")
    age = (time.time() - latest["sent"]) / 3600 if latest else None
    return ("warn" if d["problems"] else "ok"), "both centres read; %d threat%s active%s; %s" % (
        len(act), "" if len(act) == 1 else "s", ": " + ", ".join("%s (%s)" % (e["location"], e["event"]) for e in act) if act else "",
        ("latest bulletin %s %s, M%s %s, %s ago%s" % (latest["centre"], latest["event"].lower(), latest.get("mag") or "?", latest.get("location", ""), _age(int(age * 3600)),
                                                      "" if age < TSUNAMI_HOURS else " (older than the %d h kept on the map)" % TSUNAMI_HOURS)) if latest else "no bulletin seen yet"
        + ("; " + "; ".join(d["problems"]) if d["problems"] else ""))
