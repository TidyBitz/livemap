"""What covers where: contents/data/sources.json as a matrix, 'where you are' and docs/COVERAGE.md."""
import json

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .common import PKG, BORDERS, _in_ring, emit


# ------------------------------------------------------------- coverage -----
# What covers where: contents/data/sources.json is the one list of sources (hazard, regions or countries,
# what it gives, lead time, licence). `coverage` turns it into the matrix the Status tab shows, the "where you
# are" lines for the home city, and docs/COVERAGE.md (`--markdown`).
SOURCES_FILE = PKG / "data" / "sources.json"


LEAD_RANK = {"minutes": 0, "hours": 1, "days": 2, "static": 3}


def read_sources():
    return json.loads(SOURCES_FILE.read_text(encoding="utf-8"))


def country_at(lon, lat):
    """(ISO 3166-1 alpha-2, name) of the country under a point, from the Natural Earth 1:110m countries; (None, None) at sea."""
    f = BORDERS / "ne_110m_admin_0_countries.geojson"
    try:
        feats = json.loads(f.read_text(encoding="utf-8"))["features"]
    except (OSError, ValueError, KeyError):
        return None, None
    for feat in feats:
        g = feat.get("geometry") or {}
        polys = [g["coordinates"]] if g.get("type") == "Polygon" else g.get("coordinates") or [] if g.get("type") == "MultiPolygon" else []
        for poly in polys:
            if poly and _in_ring(lon, lat, [v for pt in poly[0] for v in pt[:2]]):
                p = feat.get("properties") or {}
                code = p.get("ISO_A2_EH") or p.get("ISO_A2") or ""
                return (code if code and code != "-99" else None), (p.get("NAME") or p.get("ADMIN"))
    return None, None


def region_at(regions, lon, lat):
    best = None
    for r in regions:
        b = r.get("box")
        if b and b[0] <= lon <= b[2] and b[1] <= lat <= b[3]:
            if best is None or (b[2] - b[0]) * (b[3] - b[1]) < (best["box"][2] - best["box"][0]) * (best["box"][3] - best["box"][1]):
                best = r                                      # the smallest box that holds the point
    return best or next((r for r in regions if not r.get("box")), None)


def coverage(home=None):
    """{regions, hazards, matrix: {hazard: {region: [cells]}}, here: {...}}; a cell is the source, its lead,
    what it gives and whether it is national ('US only')."""
    src = read_sources()
    regions, hazards = src["regions"], src["hazards"]
    matrix = {}
    for h in hazards:
        row = {}
        for r in regions:
            cells = []
            for so in src["sources"]:
                if so["hazard"] != h["id"]:
                    continue
                if "world" in so["regions"] or r["id"] in so["regions"]:
                    cells.append({"id": so["id"], "name": so["name"], "lead": so["lead"], "gives": so["gives"], "official": so.get("official", False),
                                  "countries": so.get("countries", []), "cadence": so["cadence"], "note": so.get("note", ""), "licence": so["licence"], "attribution": so["attribution"], "url": so["url"], "status": so.get("status", "")})
            cells.sort(key=lambda c: (LEAD_RANK.get(c["lead"], 9), 0 if c["official"] else 1, 1 if c["countries"] else 0))
            row[r["id"]] = cells
        matrix[h["id"]] = row
    here = None
    if home and home[0] is not None:
        lon, lat = home
        code, cname = country_at(lon, lat)
        reg = region_at(regions, lon, lat)
        lines = []
        for h in hazards:
            if h["id"] in ("weather", "map"):
                continue
            cells = [c for c in (matrix[h["id"]].get(reg["id"], []) if reg else []) if not c["countries"] or code in c["countries"]]
            if not cells:
                lines.append({"hazard": h["name"], "text": "no source covers this area", "lead": ""})
                continue
            best = cells[0]
            lines.append({"hazard": h["name"], "text": "%s (%s)%s" % (best["name"], best["cadence"], "; also " + ", ".join(c["name"] for c in cells[1:3]) if len(cells) > 1 else ""),
                          "lead": best["lead"], "official": best["official"]})
        here = {"country": cname, "code": code, "region": reg["name"] if reg else "", "lines": lines}
    return {"regions": regions, "hazards": hazards, "leads": src["leads"], "matrix": matrix, "here": here, "sources": src["sources"]}


def coverage_markdown(cov):
    out = ["# Coverage", "", "What covers where, and how fast: generated from `livemap/contents/data/sources.json` by `livemap-helper coverage --markdown`",
           "(`docs/SOURCES.md` has the per-feed detail). Lead: **minutes** = minutes after the event or the official warning,",
           "hours = episodic or rated reporting, days = a weekly report, static = downloaded once. *National* sources name the country.", ""]
    regs = cov["regions"]
    out.append("| Hazard | " + " | ".join(r["name"] for r in regs) + " |")
    out.append("|---|" + "---|" * len(regs))
    for h in cov["hazards"]:
        cells = []
        for r in regs:
            cs = cov["matrix"][h["id"]].get(r["id"], [])
            cells.append("<br>".join("%s%s (%s)" % ("**" if c["lead"] == "minutes" else "", c["name"].split(" (")[0] + ("**" if c["lead"] == "minutes" else ""), c["lead"] + (", " + "/".join(c["countries"]) + " only" if c["countries"] else "")) for c in cs) or "-")
        out.append("| %s | %s |" % (h["name"], " | ".join(cells)))
    out += ["", "## Sources", "", "| Source | Hazard | Covers | Gives | Lead | Cadence | Official | Licence / attribution |", "|---|---|---|---|---|---|---|---|"]
    names = {r["id"]: r["name"] for r in regs}
    for so in cov["sources"]:
        where = "worldwide" if "world" in so["regions"] else ", ".join(names.get(x, x) for x in so["regions"])
        if so.get("countries"):
            where += " (" + "/".join(so["countries"]) + " only)"
        out.append("| [%s](%s) | %s | %s | %s | %s | %s | %s | %s |" % (so["name"], so["url"], so["hazard"], where, so["gives"], so["lead"], so["cadence"], "yes" if so.get("official") else "community", so["licence"] + " - " + so["attribution"]))
    out += ["", "Blind spots this table makes visible: official flood warnings are US only (GDACS's rated events elsewhere, hours);",
            "fire incidents by name are US, Canada and the EFFIS area (satellite hotspots and GDACS events elsewhere);",
            "volcano alert levels are US only and the global report is weekly; civil alerts are Ukraine only.", ""]
    return "\n".join(out)


def cmd_coverage(args):
    home = None
    if args.home:
        try:
            lat, lon = (float(x) for x in args.home.split(",")[:2])
            home = (lon, lat)
        except ValueError:
            pass
    cov = coverage(home)
    if args.markdown:
        print(coverage_markdown(cov))
    else:
        emit(cov)
