"""The widget's Sky tab: the weather at the home place, sun and moon, tonight's sky.

`sky --lat --lon [--units d,w,clock,temp]` -> one JSON document the widget draws as it is: formatted strings in the
wallpaper's units, the hourly series behind the day strips (temperature, rain, snow, chance, day/night, cloud) and
a line of text per hour for the hover bubble.

Sources, all without a key or an account: Open-Meteo for the forecast (current, hourly for 7 days, daily) and the
air quality, NOAA SWPC for the planetary K index. Each is fetched at most every 20 minutes and kept in the data
folder, so an outage shows the last answer with its age ("as of 1 h 50 min ago") rather than nothing; the age of
each source goes out with the data so the tab can colour a stale one. Sun and moon are computed here (the sun from
passes.py's formulas, the moon's phase from a standard approximation); moonrise and moonset are not attempted.
"""
import datetime
import json
import math
import time

from .common import DATA, emit, fetch_json, read_layers_str, read_units
from .passes import elevation_of_sun

CACHE = DATA / "sky.json"
KEEP = 20 * 60                                   # ask a source again after this
FORECAST = ("https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f"
            "&current=temperature_2m,apparent_temperature,relative_humidity_2m,pressure_msl,wind_speed_10m,wind_direction_10m,weather_code,cloud_cover,is_day,precipitation"
            "&hourly=temperature_2m,precipitation_probability,precipitation,snowfall,weather_code,cloud_cover,wind_speed_10m,wind_direction_10m,is_day,relative_humidity_2m,pressure_msl"
            "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,snowfall_sum,sunrise,sunset,uv_index_max"
            "&timezone=auto&forecast_days=7&wind_speed_unit=kmh&timeformat=unixtime")
AIR = "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=%.4f&longitude=%.4f&current=us_aqi,european_aqi,pm2_5&timezone=auto&timeformat=unixtime"
KP = "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json"

# WMO weather codes, as Open-Meteo uses them
CODES = {0: "Clear", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast", 45: "Fog", 48: "Freezing fog",
         51: "Light drizzle", 53: "Drizzle", 55: "Heavy drizzle", 56: "Freezing drizzle", 57: "Freezing drizzle",
         61: "Light rain", 63: "Rain", 65: "Heavy rain", 66: "Freezing rain", 67: "Freezing rain",
         71: "Light snow", 73: "Snow", 75: "Heavy snow", 77: "Snow grains", 80: "Showers", 81: "Showers", 82: "Heavy showers",
         85: "Snow showers", 86: "Heavy snow showers", 95: "Thunderstorm", 96: "Thunderstorm with hail", 99: "Thunderstorm with hail"}
ICONS = {0: "sun", 1: "sun", 2: "partly", 3: "cloud", 45: "fog", 48: "fog", 51: "rain", 53: "rain", 55: "rain", 56: "sleet", 57: "sleet",
         61: "rain", 63: "rain", 65: "rain", 66: "sleet", 67: "sleet", 71: "snow", 73: "snow", 75: "snow", 77: "snow", 80: "rain", 81: "rain",
         82: "rain", 85: "snow", 86: "snow", 95: "storm", 96: "storm", 99: "storm"}


# ---- units -------------------------------------------------------------------------------------------------------
def units_from(arg):
    """[distance, wind, clock12, temp] from the --units string, else the wallpaper's layers.json."""
    u = list(read_units())
    if arg:
        try:
            u = [int(x) for x in str(arg).split(",")]
        except ValueError:
            pass
    while len(u) < 4:
        u.append(0)
    return u[:4]


def fahrenheit(u):
    """temp 0 follows the distance unit (miles -> °F), 1 °C, 2 °F"""
    return u[3] == 2 or (u[3] == 0 and u[0] == 1)


def temp_text(c, u, digits=0):
    if c is None:
        return "–"
    return ("%.*f°F" % (digits, c * 9 / 5 + 32)) if fahrenheit(u) else ("%.*f°C" % (digits, c))


def wind_text(kmh, u):
    from .common import wind_text as wt
    return wt(kmh, u[1])


def precip_text(mm, u):
    if mm is None:
        return "–"
    return ("%.2f in" % (mm / 25.4)) if u[0] == 1 else ("%.1f mm" % mm)


def pressure_text(hpa, u):
    if hpa is None:
        return "–"
    return ("%.2f in" % (hpa * 0.02953)) if u[0] == 1 else ("%d hPa" % round(hpa))


def compass(deg):
    return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int((deg + 22.5) // 45) % 8]


def clock(ts, tz, u, with_day=False):
    """A local time in the Units page's clock: '6:12 PM' or '18:12' (with the weekday when asked)."""
    d = datetime.datetime.fromtimestamp(ts, tz)
    if u[2]:
        t = d.strftime("%I:%M %p").lstrip("0")
    else:
        t = d.strftime("%H:%M")
    return (d.strftime("%a ") + t) if with_day else t


def hour_label(h, u):
    """'6 AM' / '06' for the strips' scale and the bubble"""
    if u[2]:
        return "12 AM" if h == 0 else ("12 PM" if h == 12 else ("%d AM" % h if h < 12 else "%d PM" % (h - 12)))
    return "%02d" % h


# ---- sun and moon ------------------------------------------------------------------------------------------------
def moon_phase(t):
    """(phase 0..1 from new through full and back, illuminated fraction, name) - a standard approximation (±0.5 d)."""
    synodic = 29.530588853
    known_new = 947182440                        # 2000-01-06 18:14 UTC
    age = ((t - known_new) / 86400) % synodic
    phase = age / synodic
    illum = (1 - math.cos(2 * math.pi * phase)) / 2
    names = ["new moon", "waxing crescent", "first quarter", "waxing gibbous", "full moon", "waning gibbous", "last quarter", "waning crescent"]
    idx = int((phase * 8 + 0.5) % 8)
    return phase, illum, names[idx]


def dark_hours(lat, lon, day_start, tz):
    """When the sky is dark enough to spot satellites (sun below -6°, civil dusk to civil dawn), the evening after
    `day_start` to the following morning: (dusk, dawn) unix times, or None when the sun never gets that low."""
    dusk = dawn = None
    t = day_start + 12 * 3600
    end = day_start + 36 * 3600
    prev = elevation_of_sun(lat, lon, t)
    while t < end:
        t += 300
        e = elevation_of_sun(lat, lon, t)
        if dusk is None and prev >= -6 > e:
            dusk = t
        elif dusk is not None and prev < -6 <= e:
            dawn = t
            break
        prev = e
    return (dusk, dawn) if dusk and dawn else None


# ---- the sources, cached ---------------------------------------------------------------------------------------
def cached(cache, key, fetch, now):
    """cache[key] = {"at", "data"} or {"at", "error", "data": the last good}: ask again after KEEP seconds."""
    entry = cache.get(key) or {}
    if now - entry.get("at", 0) < KEEP and entry.get("data") is not None and not entry.get("error"):
        return entry
    try:
        data = fetch()
        entry = {"at": now, "good_at": now, "data": data}
    except Exception as e:                       # noqa: BLE001 - the tab shows the reason beside the old data
        entry = {"at": now, "good_at": entry.get("good_at", 0), "data": entry.get("data"), "error": str(e)[:160]}
    cache[key] = entry
    return entry


def fetch_kp():
    rows = fetch_json(KP, timeout=8, what="NOAA SWPC K index")
    # [["time_tag","Kp","a_running","station_count"], ["2026-10-26 15:00:00.000","2.33","9","8"], ...]
    # ... or, from the other SWPC products, [{"time_tag": "...", "kp_index": 2, ...}, ...]
    last = None
    for r in rows:
        try:
            if isinstance(r, dict):
                kp = r.get("kp_index", r.get("Kp", r.get("estimated_kp")))
                if kp is None:
                    continue
                last = (r.get("time_tag", ""), float(kp))
            else:
                last = (r[0], float(r[1]))
        except (ValueError, TypeError, IndexError):
            continue
    if not last:
        raise ValueError("no K index rows in %d entries" % len(rows))
    return {"time": last[0], "kp": last[1]}


def kp_words(kp, lat):
    level = "quiet" if kp < 4 else "unsettled" if kp < 5 else "minor storm" if kp < 6 else "moderate storm" if kp < 7 else "strong storm"
    # the auroral oval's equatorward edge by Kp, roughly: 66° at Kp 0, about 3° per Kp step (geomagnetic, used here as geographic)
    reach = 66 - 3 * kp
    a = abs(lat)
    chance = "overhead" if a >= reach + 4 else "possible on the horizon" if a >= reach - 6 else "unlikely"
    return "Kp %.0f, %s · aurora %s at %.1f°%s" % (kp, level, chance, a, "N" if lat >= 0 else "S")


def aqi_words(aqi):
    if aqi is None:
        return "–"
    band = "good" if aqi <= 50 else "moderate" if aqi <= 100 else "unhealthy for sensitive groups" if aqi <= 150 else "unhealthy" if aqi <= 200 else "very unhealthy" if aqi <= 300 else "hazardous"
    return "AQI %d, %s" % (round(aqi), band)


def age_words(seconds):
    m = seconds / 60
    return "as of now" if m < 1.5 else "as of %d min ago" % round(m) if m < 90 else "as of %.1f h ago" % (m / 60) if m < 600 else "as of %d h ago" % round(m / 60)


# ---- the document --------------------------------------------------------------------------------------------------
def build(lat, lon, u, cache, now):
    fc = cached(cache, "forecast", lambda: fetch_json(FORECAST % (lat, lon), timeout=10, what="Open-Meteo forecast"), now)
    air = cached(cache, "air", lambda: fetch_json(AIR % (lat, lon), timeout=8, what="Open-Meteo air quality"), now)
    kp = cached(cache, "kp", fetch_kp, now)
    out = {"lat": lat, "lon": lon, "units": u, "at": now, "name": read_layers_str("home_name") or ("%.2f\u00b0%s, %.2f\u00b0%s" % (abs(lat), "N" if lat >= 0 else "S", abs(lon), "E" if lon >= 0 else "W")),
           "ages": {k: {"age": age_words(now - e["good_at"]) if e.get("good_at") else "no data yet",
                        "minutes": round((now - e["good_at"]) / 60) if e.get("good_at") else None, "error": e.get("error", "")}
                    for k, e in (("forecast", fc), ("air", air), ("kp", kp))}}
    f = fc.get("data")
    if not f:
        out["problem"] = "The forecast could not be fetched: " + (fc.get("error") or "no answer")
        return out
    tzname = f.get("timezone") or "UTC"
    offset = f.get("utc_offset_seconds", 0)
    tz = datetime.timezone(datetime.timedelta(seconds=offset), tzname)
    out["timezone"] = tzname
    cur, hr, dy = f.get("current", {}), f.get("hourly", {}), f.get("daily", {})

    # now
    code = int(cur.get("weather_code", 0) or 0)
    temps = hr.get("temperature_2m", [])
    out["now"] = {
        "temp": temp_text(cur.get("temperature_2m"), u), "feels": temp_text(cur.get("apparent_temperature"), u),
        "words": CODES.get(code, "–"), "icon": ICONS.get(code, "cloud"), "is_day": bool(cur.get("is_day", 1)),
        "wind": "%s %s" % (wind_text(cur.get("wind_speed_10m") or 0, u), compass(cur.get("wind_direction_10m") or 0)),
        "humidity": "%d %%" % round(cur.get("relative_humidity_2m") or 0), "cloud": "%d %%" % round(cur.get("cloud_cover") or 0),
        "pressure": pressure_text(cur.get("pressure_msl"), u), "time": clock(cur.get("time", now), tz, u, with_day=True),
        "high": temp_text((dy.get("temperature_2m_max") or [None])[0], u), "low": temp_text((dy.get("temperature_2m_min") or [None])[0], u),
    }
    # pressure trend: against three hours earlier in the hourly series
    try:
        times = hr["time"]
        i = max(k for k, t in enumerate(times) if t <= now)
        p_now, p_then = hr["pressure_msl"][i], hr["pressure_msl"][max(0, i - 3)]
        out["now"]["trend"] = "rising" if p_now - p_then > 1 else "falling" if p_then - p_now > 1 else "steady"
    except (KeyError, ValueError, IndexError, TypeError):
        out["now"]["trend"] = ""

    # the days: strips from the hourly series, 24 cells each, plus a line per hour for the bubble
    days = []
    d_times = dy.get("time", [])
    h_times = hr.get("time", [])
    tmin = min((x for x in temps if x is not None), default=0)
    tmax = max((x for x in temps if x is not None), default=1)
    span = max(1.0, tmax - tmin)
    for di, dstart in enumerate(d_times):
        dcode = int((dy.get("weather_code") or [0] * 7)[di] or 0)
        cells, lines, day_codes = [], [], []
        for h in range(24):
            t = dstart + h * 3600
            try:
                i = h_times.index(t)
            except ValueError:
                cells.append(None); lines.append(""); continue
            tc = hr["temperature_2m"][i]
            pr = (hr.get("precipitation") or [0] * len(h_times))[i] or 0
            sn = (hr.get("snowfall") or [0] * len(h_times))[i] or 0
            pp = (hr.get("precipitation_probability") or [0] * len(h_times))[i] or 0
            cc = (hr.get("cloud_cover") or [0] * len(h_times))[i] or 0
            hc = int((hr.get("weather_code") or [0] * len(h_times))[i] or 0)
            isday = bool((hr.get("is_day") or [1] * len(h_times))[i])
            ws = (hr.get("wind_speed_10m") or [0] * len(h_times))[i] or 0
            wd = (hr.get("wind_direction_10m") or [0] * len(h_times))[i] or 0
            if isday:
                day_codes.append(hc)
            # Open-Meteo's chance and amount come from different model fields, so a trace of drizzle can carry a
            # 0 % chance: the strip's band is the stronger of the two readings (an amount counts as a chance of its
            # own), and the bubble says "chance not given" rather than a contradictory 0 %
            strength = max(pp / 100, min(0.6, pr / 2) if pr > 0 else 0)
            chance = ("%d %% chance of %s" % (round(pp), "snow" if sn > 0 else "rain")) if pp > 0 else ("chance not given" if pr > 0 else "0 % chance")
            cells.append({"t": round((tc - tmin) / span, 3) if tc is not None else None, "p": round(strength, 2), "mm": pr, "snow": sn > 0, "day": isday, "c": round(cc / 100, 2),
                          "icon": ICONS.get(hc, "cloud")})
            lines.append("%s · %s · %s%s · %s · cloud %d %% · wind %s %s" % (
                hour_label(h, u), temp_text(tc, u), CODES.get(hc, "–"), (" (" + ("snow " if sn > 0 else "") + precip_text(pr, u) + ")") if pr > 0 else "",
                chance, round(cc), wind_text(ws, u), compass(wd)))
        # the day's icon: Open-Meteo's daily code is the worst hour of the day, so one hour of drizzle at 3 am makes a
        # dry day "rain"; keep the worst code only when the day really is wet, else the commonest daytime hour
        wet = ((dy.get("precipitation_sum") or [0] * 7)[di] or 0) >= 1 or ((dy.get("precipitation_probability_max") or [0] * 7)[di] or 0) >= 30
        if not wet and day_codes:
            dcode = max(set(day_codes), key=day_codes.count)
        sr, ss = (dy.get("sunrise") or [None] * 7)[di], (dy.get("sunset") or [None] * 7)[di]
        days.append({
            "name": "Today" if di == 0 else "Tomorrow" if di == 1 else datetime.datetime.fromtimestamp(dstart, tz).strftime("%A"),
            "short": datetime.datetime.fromtimestamp(dstart, tz).strftime("%a"), "start": dstart,
            "icon": ICONS.get(dcode, "cloud"), "words": CODES.get(dcode, "–"),
            "high": temp_text((dy.get("temperature_2m_max") or [None] * 7)[di], u), "low": temp_text((dy.get("temperature_2m_min") or [None] * 7)[di], u),
            "chance": "%d %%" % round((dy.get("precipitation_probability_max") or [0] * 7)[di] or 0),
            "rain": precip_text((dy.get("precipitation_sum") or [0] * 7)[di] or 0, u),
            "sunrise_h": ((sr - dstart) / 3600) if sr else None, "sunset_h": ((ss - dstart) / 3600) if ss else None,
            "cells": cells, "lines": lines,
        })
    out["days"] = days
    out["now_h"] = ((now - d_times[0]) / 3600) if d_times else None     # the "now" line, hours into today

    # sun and moon
    sun = {}
    if d_times:
        sr, ss = (dy.get("sunrise") or [None])[0], (dy.get("sunset") or [None])[0]
        if sr and ss:
            sun["sunrise"], sun["sunset"] = clock(sr, tz, u), clock(ss, tz, u)
            length = ss - sr
            sun["day_length"] = "%d h %02d min" % (length // 3600, (length % 3600) // 60)
        dark = dark_hours(lat, lon, d_times[0], tz)
        if dark:
            sun["dark"] = "%s – %s" % (clock(dark[0], tz, u), clock(dark[1], tz, u))
        uv = (dy.get("uv_index_max") or [None])[0]
        if uv is not None:
            sun["uv"] = "%.0f" % uv
    phase, illum, name = moon_phase(now)
    sun["moon"] = "%s, %d %% lit" % (name, round(illum * 100))
    sun["moon_phase"] = round(phase, 3)
    out["sun"] = sun

    # tonight's sky: cloud cover through the dark hours, the next visible pass, Kp, air
    tonight = {}
    try:
        dark = dark_hours(lat, lon, d_times[0], tz)
        if dark:
            cc = [hr["cloud_cover"][i] for i, t in enumerate(h_times) if dark[0] <= t <= dark[1]]
            if cc:
                m = sum(cc) / len(cc)
                tonight["cloud"] = "%d %% · %s" % (round(m), "clear" if m < 25 else "some cloud" if m < 60 else "mostly cloudy" if m < 85 else "overcast")
    except (KeyError, IndexError, TypeError, ValueError):
        pass
    try:
        from .feed import home_passes, pass_text
        passes, _cloud = home_passes(now, 1)
        if passes:
            p = passes[0]
            tonight["pass"] = "%s · %s · %s" % (p["sat"], clock(p["rise"], tz, u, with_day=True), pass_text(p))
        else:
            tonight["pass"] = "no visible pass in the next three days"
    except Exception:                            # noqa: BLE001 - passes are a bonus here
        pass
    if kp.get("data"):
        tonight["kp"] = kp_words(kp["data"]["kp"], lat)
    if air.get("data"):
        a = air["data"].get("current", {})
        tonight["air"] = aqi_words(a.get("us_aqi") if u[0] == 1 else a.get("european_aqi") if a.get("european_aqi") is not None else a.get("us_aqi"))
    out["tonight"] = tonight
    return out


def cmd_sky(args):
    try:
        lat, lon = float(args.lat), float(args.lon)
    except (TypeError, ValueError):
        home = read_layers_str("home")
        try:
            lat, lon = (float(x) for x in home.split(","))
        except (ValueError, AttributeError):
            emit({"problem": "No home place: set it under Essentials > Where you are"})
            return
    u = units_from(getattr(args, "units", None))
    now = time.time()
    try:
        cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
        if cache.get("key") != "%.3f,%.3f" % (lat, lon):
            cache = {}
    except (OSError, ValueError):
        cache = {}
    cache["key"] = "%.3f,%.3f" % (lat, lon)
    doc = build(lat, lon, u, cache, now)
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(cache), encoding="utf-8")
    except OSError:
        pass
    emit(doc)
