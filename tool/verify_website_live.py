"""Bounded production readback using the existing aggregate-worker identity.

No customer records are fetched, no apps installed, no credentials persisted.
"""
import argparse
import hashlib
import json
import os
import re
import uuid
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler, urlopen
import xml.etree.ElementTree as ET


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.meta = {}
        self.canonical = None
        self.links = []
        self.ld = []
        self.in_ld = False
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "meta":
            self.meta[attrs.get("name", attrs.get("property"))] = attrs.get("content")
        if tag == "link" and attrs.get("rel") == "canonical":
            self.canonical = attrs.get("href")
        if tag == "a":
            self.links.append(attrs.get("href", ""))
        if tag == "script" and attrs.get("type") == "application/ld+json":
            self.in_ld = True

    def handle_endtag(self, tag):
        if tag == "script":
            self.in_ld = False

    def handle_data(self, text):
        if self.in_ld:
            self.ld.append(json.loads(text))


opener = build_opener(NoRedirect)


def bounded(request, limit=524288):
    with opener.open(request, timeout=45) as response:
        raw = response.read(limit + 1)
        if len(raw) > limit:
            raise RuntimeError("Response exceeds readback transport cap")
        return raw, dict(response.headers)


def json_call(request):
    return json.loads(bounded(request)[0])


def mask(token):
    if not isinstance(token, str) or not token or "\n" in token or "\r" in token:
        raise RuntimeError("Invalid token response")
    print("::add-mask::" + token, flush=True)
    return token


def worker_token():
    tenant, client = os.environ["WORKER_TENANT_ID"], os.environ["WORKER_CLIENT_ID"]
    for value in (tenant, client):
        uuid.UUID(value)
    url = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"]
    url += ("&" if "?" in url else "?") + urlencode({"audience": "api://AzureADTokenExchange"})
    assertion = mask(json_call(Request(url, headers={
        "Authorization": "Bearer " + os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]
    }))["value"])
    body = urlencode({"client_id": client, "scope": "api://" + client + "/.default",
        "grant_type": "client_credentials",
        "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
        "client_assertion": assertion}).encode()
    return mask(json_call(Request("https://login.microsoftonline.com/" + tenant + "/oauth2/v2.0/token",
        data=body, headers={"Content-Type": "application/x-www-form-urlencoded"}))["access_token"])


def verify():
    origin = os.environ["API_ORIGIN"].rstrip("/")
    parsed = urlsplit(origin)
    if parsed.scheme != "https" or not parsed.hostname.endswith(".azurestaticapps.net") or parsed.path or parsed.query or parsed.fragment:
        raise RuntimeError("Expected the existing HTTPS SWA origin")
    config = json.loads((Path(__file__).resolve().parent.parent / "site" / "customer-config.json").read_text())
    if config["origin"] != origin:
        raise RuntimeError("Deployed canonical origin and release configuration differ")
    evidence = {"observedAt": datetime.now(timezone.utc).isoformat(), "origin": origin, "pages": {}, "downloads": {}}
    for path in ("/", "/releases/", "/console.html", "/operator-callback.html"):
        raw, headers = bounded(Request(origin + path))
        page = Page(raw.decode())
        if path in ("/", "/releases/"):
            assert page.canonical == origin + path
            assert page.meta["description"] and page.meta["og:image"]
            assert page.meta["twitter:card"] == "summary_large_image"
            assert not any("console" in link for link in page.links)
        else:
            assert "noindex" in page.meta["robots"]
            assert "noindex" in next(value for name, value in headers.items() if name.lower() == "x-robots-tag")
        evidence["pages"][path] = {"canonical": page.canonical, "noindex": "noindex" in page.meta.get("robots", ""),
            "sha256": hashlib.sha256(raw).hexdigest()}
        if path == "/":
            assert len(page.ld) == 1
            application = page.ld[0]
            assert application["@context"] == "https://schema.org" and application["@type"] == "SoftwareApplication"
            assert application["operatingSystem"] == "Windows" and "aggregateRating" not in application
            evidence["structuredData"] = application
            for arch in ("arm64", "x64"):
                assert config["release"][arch]["url"] in page.links
        if path == "/releases/":
            for arch in ("arm64", "x64"):
                assert config["release"][arch]["sha256"] in raw.decode()
    robots = bounded(Request(origin + "/robots.txt"))[0].decode()
    assert "Disallow: /console.html" in robots and "Sitemap: " + origin + "/sitemap.xml" in robots
    sitemap = bounded(Request(origin + "/sitemap.xml"))[0]
    locations = [element.text for element in ET.fromstring(sitemap).iter() if element.tag.endswith("loc")]
    assert sorted(locations) == sorted([origin + "/", origin + "/releases/"])
    evidence["sitemap"] = locations
    evidence["robots"] = robots
    social = bounded(Request(origin + "/assets/bloomstep-social.png"))[0]
    assert social[:8] == b"\x89PNG\r\n\x1a\n"
    evidence["socialImage"] = {"bytes": len(social), "sha256": hashlib.sha256(social).hexdigest()}
    for arch in ("arm64", "x64"):
        release = config["release"][arch]
        if not re.fullmatch(r"https://github\.com/Sampath-K/bloomstep/releases/download/[A-Za-z0-9.-]+/Bloomstep-[A-Za-z0-9.-]+-windows-" + arch + r"-setup\.exe", release["url"]):
            raise RuntimeError("Unexpected release asset")
        digest = hashlib.sha256()
        size = 0
        # Only public release assets follow GitHub's download redirect.
        with urlopen(release["url"], timeout=90) as response:
            while chunk := response.read(65536):
                size += len(chunk)
                if size > 150 * 1024 * 1024:
                    raise RuntimeError("Installer exceeds public readback cap")
                digest.update(chunk)
        assert digest.hexdigest() == release["sha256"]
        evidence["downloads"][arch] = {"url": release["url"], "sha256": digest.hexdigest(), "bytes": size}
    token = worker_token()
    auth = {"X-Bloomstep-Authorization": "Bearer " + token}
    for path in ("/api/sync", "/api/team/metrics", "/api/team/website"):
        try:
            bounded(Request(origin + path, headers=auth))
            raise RuntimeError("Aggregate worker reached a customer/admin route")
        except HTTPError as error:
            assert error.code == 401
    before = json_call(Request(origin + "/api/internal/website-proof", headers=auth))
    event = {"channel": "web", "event": "landing_view", "source": "unknown", "architecture": "unknown",
        "eventId": str(uuid.uuid4()), "synthetic": True}
    headers = {"Content-Type": "application/json", "User-Agent": "Bloomstep-Synthetic-Readback"}
    accepted = json_call(Request(origin + "/api/web/events", data=json.dumps(event).encode(), headers=headers))
    assert accepted == {"accepted": True, "synthetic": True}
    after = json_call(Request(origin + "/api/internal/website-proof", headers=auth))
    assert after["syntheticAccepted"] == (before["syntheticAccepted"] or 0) + 1
    assert after["realAccepted"] == before["realAccepted"], "Real traffic changed during proof; no isolation claim inferred"
    for signal in ("DNT", "Sec-GPC"):
        raw, _ = bounded(Request(origin + "/api/web/events", data=json.dumps(event).encode(),
            headers={**headers, signal: "1"}))
        assert raw == b""
    final = json_call(Request(origin + "/api/internal/website-proof", headers=auth))
    assert final == after
    evidence["funnelProof"] = {"before": before, "after": after, "privacySignals": ["DNT","Sec-GPC"],
        "marker": "synthetic=true, source=unknown; isolated from real metrics"}
    return evidence


if __name__ == "__main__":
    args = argparse.ArgumentParser()
    args.add_argument("--output", required=True)
    output = args.parse_args().output
    try:
        result = verify()
    except (AssertionError, OSError, ValueError, KeyError, RuntimeError) as error:
        # Do not expose token endpoints, private bodies or credential values.
        Path(output).write_text(json.dumps({"status": "failed", "errorType": type(error).__name__}))
        raise SystemExit("Website production readback failed; credentials and private responses omitted.")
    Path(output).write_text(json.dumps(result, indent=2))
    print("Verified live customer pages, SEO controls, exact installer checksums and isolated aggregate round trip.")
