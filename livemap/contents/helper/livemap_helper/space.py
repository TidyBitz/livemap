"""Satellites (CelesTrak TLEs, propagated here) and launches (Launch Library 2)."""
import json
import re

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .common import DATA, _http, emit, last_good, stale_note


# ---------------------------------------------------------------- space -----
# Satellites: two-line elements from CelesTrak (no key), propagated here with a Kepler + J2 model - the
# secular part of SGP4 (nodal and apsidal precession, mean-motion correction) without drag and short-period
# terms. For a low orbit with elements less than a day old that is within a few km of the full model, which
# is well under a pixel on this map. Elements are refreshed every six hours.
CELESTRAK = "https://celestrak.org/NORAD/elements/gp.php?CATNR=%s&FORMAT=TLE"


SATS = [("ISS", "25544", "International Space Station"), ("Hubble", "20580", "Hubble Space Telescope"),
        ("Tiangong", "48274", "Tiangong Chinese Space Station")]


TLES = DATA / "tle.json"


MU, RE, J2 = 398600.4418, 6378.137, 1.08262668e-3


def fetch_tles(max_age_h=6):
    import time
    try:
        c = json.loads(TLES.read_text(encoding="utf-8"))
        if time.time() - c.get("at", 0) < max_age_h * 3600 and len(c.get("tles", {})) == len(SATS):
            return c["tles"]
    except (OSError, ValueError):
        c = {}
    tles = dict(c.get("tles") or {})
    for short, catnr, _long in SATS:
        try:
            lines = _http(CELESTRAK % catnr)[2].decode("ascii", "replace").strip().splitlines()
            lines = [l.rstrip() for l in lines if l.strip()]
            if len(lines) >= 3 and lines[-2].startswith("1 ") and lines[-1].startswith("2 "):
                tles[short] = [lines[-3].strip(), lines[-2], lines[-1]]
        except Exception:
            pass
    if tles:
        try:
            TLES.parent.mkdir(parents=True, exist_ok=True)
            TLES.write_text(json.dumps({"at": time.time(), "tles": tles}), encoding="utf-8")
        except OSError:
            pass
    return tles


def parse_tle(l1, l2):
    import math
    from datetime import datetime, timezone, timedelta
    yy = int(l1[18:20]); year = 2000 + yy if yy < 57 else 1900 + yy
    epoch = (datetime(year, 1, 1, tzinfo=timezone.utc) + timedelta(days=float(l1[20:32]) - 1)).timestamp()
    ndot = float(l1[33:43])                                   # rev/day^2 (already halved in the TLE)
    return {"epoch": epoch, "ndot": ndot, "inc": math.radians(float(l2[8:16])), "raan": math.radians(float(l2[17:25])),
            "ecc": float("0." + l2[26:33].strip()), "argp": math.radians(float(l2[34:42])),
            "ma": math.radians(float(l2[43:51])), "n": float(l2[52:63])}


def gmst(t):
    """Greenwich mean sidereal time (radians) for a unix time."""
    import math
    jd = t / 86400.0 + 2440587.5
    T = (jd - 2451545.0) / 36525.0
    g = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * T * T - T * T * T / 38710000.0
    return math.radians(g % 360.0)


def propagate(el, t):
    """(lat, lon, altitude km) of a TLE at unix time t. Kepler + J2 secular terms (see the note above)."""
    import math
    dt = t - el["epoch"]
    n0 = el["n"] * 2 * math.pi / 86400.0                       # rad/s (Kozai mean motion)
    e, i = el["ecc"], el["inc"]
    cosi, x = math.cos(i), 1 - e * e
    a1 = (MU / (n0 * n0)) ** (1 / 3)
    d1 = 1.5 * J2 * RE * RE / (a1 * a1) * (3 * cosi * cosi - 1) / (2 * x ** 1.5)
    a0 = a1 * (1 - d1 / 3 - d1 * d1 - 134 * d1 ** 3 / 81)
    d0 = 1.5 * J2 * RE * RE / (a0 * a0) * (3 * cosi * cosi - 1) / (2 * x ** 1.5)
    n = n0 / (1 + d0)                                          # Brouwer mean motion
    a = a0 / (1 - d0)
    p = a * x
    k = 1.5 * J2 * (RE / p) ** 2
    raan = el["raan"] - k * n * cosi * dt
    argp = el["argp"] + 0.5 * k * n * (5 * cosi * cosi - 1) * dt
    mdot = n * (1 + 0.5 * k * math.sqrt(x) * (3 * cosi * cosi - 1))
    m = el["ma"] + mdot * dt + el["ndot"] * 2 * math.pi / 86400.0 ** 2 * dt * dt
    m = m % (2 * math.pi)
    E = m if e < 0.8 else math.pi                               # Kepler's equation, Newton
    for _ in range(12):
        E -= (E - e * math.sin(E) - m) / (1 - e * math.cos(E))
    nu = 2 * math.atan2(math.sqrt(1 + e) * math.sin(E / 2), math.sqrt(1 - e) * math.cos(E / 2))
    r = a * x / (1 + e * math.cos(nu))
    u = argp + nu                                              # argument of latitude
    cu, su, cO, sO, si = math.cos(u), math.sin(u), math.cos(raan), math.sin(raan), math.sin(i)
    X = r * (cO * cu - sO * su * cosi)
    Y = r * (sO * cu + cO * su * cosi)
    Z = r * (su * si)
    lon = (math.degrees(math.atan2(Y, X) - gmst(t)) + 540) % 360 - 180
    lat = math.degrees(math.atan2(Z, math.sqrt(X * X + Y * Y)))
    lat += math.degrees(0.00335 * math.sin(2 * math.radians(lat)))   # geocentric -> geodetic, first order
    return lat, lon, r - RE


def cmd_sats(args):
    """Positions now and a ground track for the next `--ahead` minutes (a point every 30 s), so the wallpaper
    can move the marker itself between two runs of this command."""
    import time
    note, out, now = "", [], time.time()
    try:
        tles = fetch_tles()
    except Exception as e:
        tles, note = {}, "Satellites: %s" % e
    for short, _catnr, longname in SATS:
        tle = tles.get(short)
        if not tle:
            note = note or "Satellites: no orbital elements for %s yet (CelesTrak unreachable?)" % short
            continue
        try:
            el = parse_tle(tle[1], tle[2])
            lat, lon, alt = propagate(el, now)
            track = []
            for k in range(-args.behind * 2, args.ahead * 2 + 1):
                t = now + k * 30
                la, lo, _ = propagate(el, t)
                track.append([round(t), round(lo, 3), round(la, 3)])
            period = 1440.0 / el["n"]
            out.append({"name": short, "long_name": longname, "lat": round(lat, 3), "lon": round(lon, 3), "alt_km": round(alt),
                        "period_min": round(period, 1), "track": track, "tle_age_h": round((now - el["epoch"]) / 3600, 1)})
        except Exception as e:
            note = "Satellites: %s: %s" % (short, e)
    if args.table:
        print(note or "%d satellites (CelesTrak elements, Kepler + J2 propagation)" % len(out))
        for sat in out:
            print("  %-9s at %7.2f, %8.2f  %4d km  period %.1f min  elements %.0f h old" % (sat["name"], sat["lat"], sat["lon"], sat["alt_km"], sat["period_min"], sat["tle_age_h"]))
    else:
        emit({"sats": out, "note": note})


def chk_sats():
    tles = fetch_tles()
    missing = [s[0] for s in SATS if s[0] not in tles]
    import time
    ages = ["%s %.0f h" % (k, (time.time() - parse_tle(v[1], v[2])["epoch"]) / 3600) for k, v in tles.items()]
    return ("warn" if missing else "ok"), "elements for %s%s" % (", ".join(ages) or "nothing", "; missing " + ", ".join(missing) if missing else "")


# Launches: The Space Devs' Launch Library 2 (free, no key, 15 requests an hour), cached for an hour.
LL2 = "https://ll.thespacedevs.com/2.2.0/launch/upcoming/?limit=20&hide_recent_previous=true"


LAUNCHES = DATA / "launches.json"
ASTRONAUTS = DATA / "astronauts.json"
LL2_IN_SPACE = "https://ll.thespacedevs.com/2.2.0/astronaut/?in_space=true&limit=40&format=json"


# A flag for a crew member: LL2 gives a demonym ("American") and the agency's ISO 3166 alpha-3 code ("USA"; a list
# for ESA). The demonym decides, the agency's code is the fallback; an unknown one gets no flag.
DEMONYMS = {"american": "US", "russian": "RU", "chinese": "CN", "japanese": "JP", "canadian": "CA", "french": "FR", "german": "DE",
            "italian": "IT", "british": "GB", "english": "GB", "scottish": "GB", "danish": "DK", "swedish": "SE", "belgian": "BE",
            "dutch": "NL", "spanish": "ES", "swiss": "CH", "emirati": "AE", "saudi": "SA", "saudi arabian": "SA", "indian": "IN",
            "turkish": "TR", "polish": "PL", "hungarian": "HU", "australian": "AU", "brazilian": "BR", "israeli": "IL",
            "south korean": "KR", "korean": "KR", "kazakh": "KZ", "kazakhstani": "KZ", "belarusian": "BY", "norwegian": "NO",
            "austrian": "AT", "portuguese": "PT", "mexican": "MX", "new zealander": "NZ", "malaysian": "MY", "thai": "TH",
            "egyptian": "EG", "nigerian": "NG", "south african": "ZA", "argentine": "AR", "argentinian": "AR", "ukrainian": "UA",
            "czech": "CZ", "slovak": "SK", "romanian": "RO", "greek": "GR", "irish": "IE", "finnish": "FI", "luxembourger": "LU",
            "bulgarian": "BG", "cuban": "CU", "vietnamese": "VN", "mongolian": "MN", "syrian": "SY", "afghan": "AF", "indonesian": "ID",
            "peruvian": "PE", "chilean": "CL", "colombian": "CO", "costa rican": "CR", "iranian": "IR", "pakistani": "PK",
            "singaporean": "SG", "taiwanese": "TW", "omani": "OM", "qatari": "QA", "kuwaiti": "KW", "lebanese": "LB"}
ALPHA3 = {"USA": "US", "RUS": "RU", "CHN": "CN", "JPN": "JP", "CAN": "CA", "FRA": "FR", "DEU": "DE", "ITA": "IT", "GBR": "GB", "DNK": "DK",
          "SWE": "SE", "BEL": "BE", "NLD": "NL", "ESP": "ES", "CHE": "CH", "ARE": "AE", "SAU": "SA", "IND": "IN", "TUR": "TR", "POL": "PL",
          "HUN": "HU", "AUS": "AU", "BRA": "BR", "ISR": "IL", "KOR": "KR", "KAZ": "KZ", "BLR": "BY", "NOR": "NO", "AUT": "AT", "PRT": "PT",
          "MEX": "MX", "NZL": "NZ", "MYS": "MY", "THA": "TH", "EGY": "EG", "NGA": "NG", "ZAF": "ZA", "ARG": "AR", "UKR": "UA", "CZE": "CZ",
          "SVK": "SK", "ROU": "RO", "GRC": "GR", "IRL": "IE", "FIN": "FI", "LUX": "LU"}


def flag_for(nationality, agency_code=""):
    """The flag emoji (two regional-indicator letters) for a nationality, or "" when it is not known."""
    code = ""
    for part in str(nationality or "").replace("/", ",").split(","):
        code = DEMONYMS.get(part.strip().lower(), "")
        if code:
            break
    if not code:
        codes = [c.strip().upper() for c in str(agency_code or "").split(",") if c.strip()]
        if len(codes) == 1:
            code = ALPHA3.get(codes[0], "")
    if len(code) != 2:
        return ""
    return "".join(chr(0x1F1E6 + ord(ch) - 65) for ch in code)


def fetch_crews(max_age_h=4):
    """Who is in space right now, from Launch Library 2 (the same source as the launches, so no new host), kept
    for four hours: LL2's free tier allows 15 requests an hour and the feed runs every five minutes. Returns
    {"ISS": [...], "Tiangong": [...]} of {name, country, agency, since, days}: a person is put on Tiangong
    when their agency is Chinese, on the ISS otherwise (LL2 does not say which station)."""
    import time
    from datetime import datetime, timezone
    now = time.time()
    try:
        c = json.loads(ASTRONAUTS.read_text(encoding="utf-8"))
        if now - c.get("at", 0) < max_age_h * 3600 and isinstance(c.get("crews"), dict):
            return c["crews"]
    except (OSError, ValueError):
        c = {}
    body = json.loads(_http(LL2_IN_SPACE, timeout=12)[2].decode("utf-8", "replace"))
    crews = {"ISS": [], "Tiangong": []}
    for a in body.get("results", []):
        ag = a.get("agency") or {}
        country = a.get("nationality") or ag.get("country_code") or ""
        if isinstance(country, list):                                  # LL2 2.3 shape: [{"name": ...}]
            country = ", ".join(str(x.get("name") or x.get("nationality_name") or "") for x in country if isinstance(x, dict))
        chinese = (ag.get("country_code") or "").upper() in ("CHN", "CN") or "china" in (ag.get("name") or "").lower() or "chinese" in str(country).lower()
        since, days = "", None
        try:
            t = datetime.strptime(str(a.get("last_flight"))[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc).timestamp()
            since, days = time.strftime("%d %b %Y", time.gmtime(t)), int((now - t) // 86400)
        except (TypeError, ValueError):
            pass
        # LL2 counts whatever it has launched and not brought back as "in space": Starman in his Roadster (2018,
        # nationality "Earthling") is one. Nobody has stayed on a station longer than 371 days, so anyone up for
        # over 450 is not aboard either of them.
        if str(country).lower() == "earthling" or (days is not None and days > 450) or "starman" in (a.get("name") or "").lower():
            continue
        crews["Tiangong" if chinese else "ISS"].append({"name": a.get("name") or "", "country": str(country), "agency": ag.get("abbrev") or ag.get("name") or "",
                                                       "flag": flag_for(country, ag.get("country_code")),
                                                       "since": since, "days": days, "image": a.get("profile_image_thumbnail") or ""})
    for k in crews:
        crews[k].sort(key=lambda x: -(x["days"] if x["days"] is not None else -1))
    try:
        ASTRONAUTS.parent.mkdir(parents=True, exist_ok=True)
        ASTRONAUTS.write_text(json.dumps({"at": now, "crews": crews}), encoding="utf-8")
    except OSError:
        pass
    return crews


def fetch_launches(max_age_h=1):
    import time
    try:
        c = json.loads(LAUNCHES.read_text(encoding="utf-8"))
        if time.time() - c.get("at", 0) < max_age_h * 3600:
            return c["launches"]
    except (OSError, ValueError):
        pass
    from datetime import datetime, timezone
    body = json.loads(_http(LL2)[2].decode("utf-8", "replace"))
    out = []
    for L in body.get("results", []):
        pad = L.get("pad") or {}
        try:
            lat, lon = float(pad.get("latitude")), float(pad.get("longitude"))
        except (TypeError, ValueError):
            continue
        try:
            net = datetime.strptime(L["net"][:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc).timestamp()
        except (KeyError, ValueError, TypeError):
            continue
        rocket = ((L.get("rocket") or {}).get("configuration") or {})
        mission = (L.get("mission") or {}).get("name") or ""
        parts = [p.strip() for p in re.split(r",\s*", re.sub(r"\s*\(.*?\)\s*$", "", mission)) if p.strip()]
        if len(parts) > 1 and len(set(parts)) < len(parts):        # "Owlright, Owlright, Owlright" -> "Owlright x3"
            seen = []
            for pnm in parts:
                if pnm not in seen:
                    seen.append(pnm)
            mission = ", ".join("%s \u00d7%d" % (pnm, parts.count(pnm)) if parts.count(pnm) > 1 else pnm for pnm in seen)
        vids = sorted([v for v in (L.get("vidURLs") or []) if isinstance(v, dict) and str(v.get("url", "")).startswith("https://")], key=lambda v: v.get("priority") or 99)
        out.append({"id": L.get("id"), "name": L.get("name", ""), "rocket": rocket.get("full_name") or rocket.get("name") or "",
                    "videos": [{"url": v["url"], "title": v.get("title") or ""} for v in vids][:4], "webcast_live": bool(L.get("webcast_live")),
                    "mission": mission, "orbit": (((L.get("mission") or {}).get("orbit") or {}).get("abbrev") or ""),
                    "provider": ((L.get("launch_service_provider") or {}).get("name") or ""),
                    "status": ((L.get("status") or {}).get("abbrev") or ""), "net": net,
                    "pad": pad.get("name") or "", "site": ((pad.get("location") or {}).get("name") or ""), "lat": lat, "lon": lon,
                    "status_name": ((L.get("status") or {}).get("name") or ""), "window_end": L.get("window_end") or "",
                    "image": (L.get("image") if isinstance(L.get("image"), str) else (L.get("image") or {}).get("image_url")) or ""})
    try:
        LAUNCHES.parent.mkdir(parents=True, exist_ok=True)
        LAUNCHES.write_text(json.dumps({"at": time.time(), "launches": out}), encoding="utf-8")
    except OSError:
        pass
    return out


def cmd_launches(args):
    import time
    note, launches = "", []
    data, stale_h, err = last_good("launches", fetch_launches)
    launches = data or []
    if err:
        note = stale_note("Launches", stale_h, err, args.stale)
    if args.table:
        print(note or "%d upcoming launches (Launch Library 2, The Space Devs)" % len(launches))
        for L in launches:
            print("  T%+7.1f h  %-6s %-40s %-28s %s" % ((L["net"] - time.time()) / 3600, L["status"], L["name"][:40], L["site"][:28], L["orbit"]))
    else:
        emit({"launches": launches, "note": note})


def chk_launches():
    import time
    launches = fetch_launches()
    soon = [L for L in launches if L["net"] > time.time()]
    nxt = soon[0] if soon else None
    return "ok", "%d upcoming launches%s" % (len(launches), "; next: %s in %.1f h (%s)" % (nxt["name"], (nxt["net"] - time.time()) / 3600, nxt["status"]) if nxt else "")
