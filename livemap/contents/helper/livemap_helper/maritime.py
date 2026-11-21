"""Maritime security incidents: UKMTO (United Kingdom Maritime Trade Operations), read from the Royal Navy's API."""
import json
import re

from .common import _age, emit, last_good, stale_note, fetch_json


# ----------------------------------------------------------- maritime -----
# UKMTO is the Royal Navy's point of contact for merchant shipping in the Indian Ocean, the Red Sea, the Gulf of
# Aden, the Arabian Gulf and the Strait of Hormuz: attacks, attempted and illegal boardings, hijacks, kidnaps,
# suspicious approaches, electronic interference, and advisories, each published within hours as a warning
# with a position, the sea area, the vessel type and a narrative. ukmto.org itself is a Next.js page that
# holds none of this: the page asks the Royal Navy's API, which answers plain JSON to anyone with no key,
# cookie or browser headers (checked from a desktop, October 2026). Every current incident comes in one list
# (the site keeps roughly a month); `incident/filters` names the sea areas and types. Crown copyright.
UKMTO_ALL = "https://sccd.royalnavy.mod.uk/api/ukmto/all"
UKMTO_FILTERS = "https://sccd.royalnavy.mod.uk/api/ukmto/incident/filters"
UKMTO_PAGE = "https://www.ukmto.org/indian-ocean/recent-incidents"

# MDAT-GoG (Maritime Domain Awareness for Trade - Gulf of Guinea), the French and Royal Navies' counterpart of
# UKMTO for West Africa, from Senegal round to Angola. Its public site, SEVERINE (French Ministry of the Armed
# Forces), is a map fed by a plain JSON API with no key or cookie: a markers list for a date window (id,
# position, the type's colour and icon), and one record per event (title, start, description, position, the
# type and its family - Piracy, Armed robbery against ships, Illegal activities, Conflict spillover,
# Information). Events are few (a dozen a year lately) and never change once published, so each is fetched
# once and kept. Recorded from a browser in November 2026.
MDAT_MARKERS = "https://severine-ext.vigie.defense.gouv.fr/api/events/markers?dateStart=%d&dateEnd=%d"
MDAT_EVENT = "https://severine-ext.vigie.defense.gouv.fr/api/events/%s"
MDAT_PAGE = "https://severine-ext.vigie.defense.gouv.fr/events/details/%s"


# the incident type -> how much it matters: 3 a vessel or crew taken or an attack with a red pin, 2 an attack
# or a boarding, 1 a suspicious approach, interference, an advisory. The API's own `incidentTypeLevel` is not
# a severity (Advisory is 3 there, Attack 1), so it is kept in the record but not used for this.
MARITIME_LEVELS = {"hijack": 3, "kidnap": 3, "kidnapping": 3, "attack": 2, "attempted boarding": 2, "illegal boarding": 2, "boarding": 2,
                   "sea robbery": 2, "sea theft": 2, "suspicious activity": 1, "electronic interference": 1, "advisory": 1, "other": 1}


MARITIME_DAYS = 30                                                         # older incidents leave the list (the site keeps about a month)


def _epoch(text):
    from datetime import datetime, timezone
    try:
        return datetime.strptime(str(text)[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc).timestamp()
    except (ValueError, TypeError):
        return None


def _clean(text):
    """The narrative as one paragraph per blank line: the API's \\r\\n line breaks inside a sentence are joined."""
    text = str(text or "").replace("\r\n", "\n").replace("\r", "\n")
    paras = [" ".join(p.split()) for p in re.split(r"\n\s*\n", text)]
    return "\n".join(p for p in paras if p)


def maritime_level(type_name, pin="", pirate=False):
    name = (type_name or "").strip().lower()
    level = MARITIME_LEVELS.get(name)
    if level is None:
        level = next((v for k, v in MARITIME_LEVELS.items() if k in name), 1)
    if pirate:
        level = 3
    elif level == 2 and str(pin or "").strip().lower() == "red":
        level = 3
    return level


def parse_incidents(data):
    """The API's list -> records, newest first. Every record keeps the source's own strings (type, place, pin)
    and gets the contract keys the feed and the layer read: kind, id, when, lat, lon, title, level."""
    if isinstance(data, dict):
        data = data.get("incidents") or data.get("items") or data.get("data") or []
    out = []
    for r in data if isinstance(data, list) else []:
        if not isinstance(r, dict):
            continue
        try:
            lat, lon = float(r["locationLatitude"]), float(r["locationLongitude"])
        except (KeyError, TypeError, ValueError):
            continue
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            continue
        when = _epoch(r.get("utcDateOfIncident")) or _epoch(r.get("utcDateCreated"))
        if not when:
            continue
        number = r.get("incidentNumber")
        type_name = " ".join(str(r.get("incidentTypeName") or "Incident").split()).title()
        pin = str(r.get("pinColour") or "").strip().title()
        pirate = bool(r.get("vesselUnderPirateControl"))
        vessel_type = " ".join(str(r.get("vesselType") or "").split()).lower()
        vessel = " ".join(str(r.get("vesselName") or "").split())
        if len(vessel) < 3 or vessel.lower() in ("vessel", "merchant", "tanker", "tkr", "mv", "n/a", "unknown"):
            vessel = ""                                                 # ".", "-", "MERCHANT": the name is withheld
        try:
            crew = int(r.get("crewHeld") or 0)
        except (TypeError, ValueError):
            crew = 0
        out.append({"kind": "maritime", "id": str(r.get("sitecoreId") or number or "%s:%s" % (lat, lon)), "number": number,
                    "issuer": str(r.get("incidentIssuer") or "UKMTO"), "type": type_name, "type_level": r.get("incidentTypeLevel"), "pin": pin,
                    "level": maritime_level(type_name, pin, pirate), "when": when, "published": _epoch(r.get("utcDateCreated")) or when,
                    "lat": lat, "lon": lon, "place": " ".join(str(r.get("place") or "").split()), "region": str(r.get("region") or ""),
                    "vessel_type": vessel_type, "vessel": vessel, "pirate_control": pirate, "crew_held": crew,
                    "taken": _epoch(r.get("dateVesselTaken")), "text": _clean(r.get("otherDetails"))[:1200],
                    "title": "%s · %s" % (type_name, " ".join(str(r.get("place") or "").split()) or "at sea"), "url": UKMTO_PAGE})
    out.sort(key=lambda it: -it["when"])
    return out


def parse_mdat_event(d, marker=None):
    """One SEVERINE event record -> the maritime record shape. The marker (from the list) carries the position
    when the record has none; the type's family becomes `category`, its label the type."""
    if not isinstance(d, dict) or not d.get("id"):
        return None
    try:
        lat, lon = float(d.get("lat") if d.get("lat") not in (None, "") else (marker or {}).get("lat")), float(d.get("lon") if d.get("lon") not in (None, "") else (marker or {}).get("lon"))
    except (TypeError, ValueError):
        return None
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return None
    try:
        when = float(d.get("start"))
    except (TypeError, ValueError):
        return None
    ty = d.get("type") or {}
    type_name = " ".join(str(ty.get("label") or "Incident").split())
    family = " ".join(str((ty.get("parent") or {}).get("label") or "").split())
    label = " ".join(str(d.get("label") or "").split())
    # the place is the label's tail: "Attempted boarding off Soyo, Angola" -> "off Soyo, Angola"
    place = label
    prefixes = sorted({type_name, type_name.split(" / ")[0], "Kidnapping", "Sea theft", "Sea robbery", "Suspicious activity", "Attempted boarding", "Illegal boarding"}, key=len, reverse=True)
    for prefix in prefixes:                                       # longest first, and only a whole word: "Kidnap" must not eat "Kidnapping"
        if prefix and label.lower().startswith(prefix.lower() + " "):
            place = label[len(prefix):].strip(" -:,")
            break
    pin = str(ty.get("color") or (marker or {}).get("color") or "")
    return {"kind": "maritime", "id": "mdat:%s" % d["id"], "number": None, "issuer": "MDAT-GoG", "type": type_name.split(" / ")[0].title() if type_name.lower().startswith("illegal boarding") else type_name.capitalize(),
            "category": family, "type_level": None, "pin": {"#000000": "Black", "#F4C328": "Yellow", "#E5DB2C": "Yellow", "#FFFFCC": "Pale"}.get(pin.upper(), pin),
            "level": 3 if family.lower() == "conflict spillover" and "attack" in type_name.lower() else maritime_level(type_name.replace(" / ", " / "), "", False),
            "when": when, "published": when, "lat": lat, "lon": lon, "place": place, "region": "GoG",
            "vessel_type": "", "vessel": "", "pirate_control": False, "crew_held": 0, "taken": None,
            "text": _clean(d.get("description"))[:1200], "title": "%s \u00b7 %s" % (type_name.split(" / ")[0].capitalize(), place or "Gulf of Guinea"),
            "url": MDAT_PAGE % d["id"]}


def fetch_mdat(now=None):
    """The Gulf of Guinea: the markers of the last MARITIME_DAYS (plus a margin), each new one's record fetched once
    and kept in DATA/mdat-events.json; records never change once published."""
    import time
    from .common import DATA
    now = now if now is not None else time.time()
    markers = fetch_json(MDAT_MARKERS % (int(now - (MARITIME_DAYS + 7) * 86400), int(now + 86400)), timeout=15, what="MDAT-GoG markers")
    if not isinstance(markers, list):
        raise RuntimeError("MDAT-GoG answered a shape the parser does not know")
    store = DATA / "mdat-events.json"
    try:
        kept = json.loads(store.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        kept = {}
    out, fetched = [], 0
    for m in markers:
        if not isinstance(m, dict) or not m.get("id"):
            continue
        d = kept.get(m["id"])
        if d is None and fetched < 20:                                  # a burst of new events: the rest next time
            try:
                d = fetch_json(MDAT_EVENT % m["id"], timeout=12, what="MDAT-GoG event")
                fetched += 1
                if isinstance(d, dict) and d.get("id"):
                    kept[m["id"]] = d
            except Exception:                                          # noqa: BLE001 - this one next time
                d = None
        rec = parse_mdat_event(d, m) if d else None
        if rec:
            out.append(rec)
    if fetched:
        try:
            store.parent.mkdir(parents=True, exist_ok=True)
            store.write_text(json.dumps(kept, ensure_ascii=False), encoding="utf-8")
        except OSError:
            pass
    out.sort(key=lambda it: -it["when"])
    return out


def fetch_maritime():
    """Every centre's incidents in one list; a centre that fails is reported, not fatal, unless both fail."""
    import time
    problems, incidents = [], []
    try:
        data = fetch_json(UKMTO_ALL, timeout=15, what="UKMTO incidents")
        got = parse_incidents(data)
        if not got and (isinstance(data, list) and data):
            raise RuntimeError("UKMTO answered %d records in a shape the parser does not know" % len(data))
        incidents += got
    except Exception as e:                                             # noqa: BLE001
        problems.append("UKMTO: %s" % e)
    try:
        incidents += fetch_mdat()
    except Exception as e:                                             # noqa: BLE001
        problems.append("MDAT-GoG: %s" % e)
    if len(problems) == 2:
        raise RuntimeError("; ".join(problems))
    cutoff = time.time() - MARITIME_DAYS * 86400
    incidents.sort(key=lambda it: -it["when"])
    return {"incidents": [it for it in incidents if it["when"] >= cutoff], "read": time.time(), "problems": problems}


def maritime_cached(max_age_min=15):
    import time
    from .common import DATA
    f = DATA / "last-maritime.json"
    try:
        c = json.loads(f.read_text(encoding="utf-8"))
        if time.time() - c.get("at", 0) < max_age_min * 60:
            return c["data"], 0.0, ""
    except (OSError, ValueError, KeyError):
        pass
    return last_good("maritime", fetch_maritime)


def cmd_maritime(args):
    import time
    data, stale_h, err = maritime_cached(args.max_age)
    note = stale_note("Maritime incidents", stale_h, err, args.stale) if err else ""
    items = (data or {}).get("incidents", [])
    if args.days:
        cutoff = time.time() - args.days * 86400
        items = [it for it in items if it["when"] >= cutoff]
    if args.table:
        print(note or "%d maritime incidents in the last %s days" % (len(items), args.days or MARITIME_DAYS))
        for it in items:
            print("  %-4s %-16s L%d %-6s %-22s %-8s %s" % (it.get("number") or "", it["type"][:16], it["level"], it["pin"][:6], it["place"][:22], it["vessel_type"][:8],
                                                        _age(int(time.time() - it["when"])) + " ago"))
    else:
        emit({"incidents": items, "note": note})


def chk_mdat():
    import time
    items = fetch_mdat()
    week = [it for it in items if time.time() - it["when"] < 7 * 86400]
    return "ok", "%d events in the Gulf of Guinea in the last %d days, %d this week%s" % (
        len(items), MARITIME_DAYS + 7, len(week),
        "; latest %s, %s, %s ago" % (items[0]["type"].lower(), items[0]["place"], _age(int(time.time() - items[0]["when"]))) if items else "")


def chk_maritime():
    import time
    data = fetch_json(UKMTO_ALL, timeout=15, what="UKMTO incidents")
    items = parse_incidents(data)
    cutoff = time.time() - MARITIME_DAYS * 86400
    items = [it for it in items if it["when"] >= cutoff]
    day = [it for it in items if time.time() - it["when"] < 86400]
    week = [it for it in items if time.time() - it["when"] < 7 * 86400]
    places = {}
    for it in week:
        places[it["place"]] = places.get(it["place"], 0) + 1
    busiest = sorted(places.items(), key=lambda kv: -kv[1])[:3]
    return "ok", "%d incidents listed (the last %d days); %d in the past day, %d this week%s%s" % (
        len(items), MARITIME_DAYS, len(day), len(week),
        ": " + ", ".join("%s (%d)" % kv for kv in busiest) if busiest else "",
        "; latest %s, %s, %s ago" % (items[0]["type"].lower(), items[0]["place"], _age(int(time.time() - items[0]["when"]))) if items else "")
