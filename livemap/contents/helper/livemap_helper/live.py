"""`live-url URL`: the YouTube broadcast that a channel's /live page is showing right now.

youtube.com/@NASA/live names no video: when the channel is live YouTube redirects it to the broadcast's watch page,
and when it is not the channel page comes back instead. The widget cannot do this itself reliably (its XMLHttpRequest
is sent from a bare QML context and YouTube answers it with a consent or a bot page), so the helper asks with a
browser's headers, follows the redirect, and reads the page three ways: the redirect's own URL, the canonical link,
and the player data (`"isLiveNow":true` beside a videoId). Answers are kept for ten minutes so flipping the Live
tab's menu does not ask YouTube every time."""
import json
import re
import time
import urllib.request

from .common import DATA, emit

CACHE = DATA / "live-urls.json"
KEEP = 600
BROWSER = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
           "Accept-Language": "en-US,en;q=0.8", "Cookie": "CONSENT=YES+; SOCS=CAI"}
VIDEO = re.compile(r"[?&]v=([\w-]{11})")


def video_from_page(final_url, html):
    m = VIDEO.search(final_url or "")
    if m:
        return m.group(1)
    m = re.search(r'<link rel="canonical" href="https://www\.youtube\.com/watch\?v=([\w-]{11})"', html)
    if m:
        return m.group(1)
    # the player data: the videoId whose details say it is live now
    ids = list(re.finditer(r'"videoId":"([\w-]{11})"', html))
    for i, m in enumerate(ids):                    # each id's own stretch of the page, up to the next id
        end = ids[i + 1].start() if i + 1 < len(ids) else m.end() + 1500
        window = html[m.end():min(end, m.end() + 1500)]
        if '"isLiveNow":true' in window or '"isLive":true' in window:
            return m.group(1)
    return ""


def resolve(url, timeout=8):
    """(video id or "", how): a browser-like GET of the /live page."""
    if not url.startswith("https://www.youtube.com/") and not url.startswith("https://youtube.com/"):
        raise ValueError("not a YouTube URL")
    req = urllib.request.Request(url, headers=BROWSER)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        final = r.geturl()
        body = r.read(3 * 1024 * 1024).decode("utf-8", "replace")
    vid = video_from_page(final, body)
    return vid, ("redirect" if VIDEO.search(final or "") else "page" if vid else "nothing live")


def cmd_live_url(args):
    url = args.url
    try:
        cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
    except (OSError, ValueError):
        cache = {}
    now = time.time()
    hit = cache.get(url)
    if hit and now - hit.get("at", 0) < KEEP and not getattr(args, "fresh", False):
        emit(dict(hit, url=url, cached=True))
        return
    try:
        vid, how = resolve(url)
        result = {"video": vid, "how": how, "at": now}
    except Exception as e:                       # noqa: BLE001 - the widget shows the reason
        result = {"video": "", "how": "error", "error": str(e)[:160], "at": now}
    cache[url] = result
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(cache), encoding="utf-8")
    except OSError:
        pass
    emit(dict(result, url=url, cached=False))
