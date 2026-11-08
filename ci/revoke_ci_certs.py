"""Revokes the throwaway Apple Development certificates that earlier CI runs made.

Each TestFlight run starts on a fresh Mac with an empty keychain, so Xcode makes a new
development certificate to sign the archive. Apple caps how many an account can hold, and
once the cap is hit every build fails with "Choose a certificate to revoke". The runners
that held those certificates are gone, so they're useless. This only touches development
certificates whose name says "Created via API" (what Xcode names the ones it makes with an
API key). Certificates made in Xcode on a Mac, and all distribution certificates, are left alone.

Certificates belong to the whole team, not one app, so another repo's CI (newlyweb's admin app) may be
signing with one right now. Only certificates more than MIN_AGE_HOURS old are revoked, so two
repos uploading at the same time don't pull each other's certificate mid-build. Apple gives
no creation date, but development certificates last a year, so age comes from the expiry.

Needs ASC_KEY_ID, ASC_ISSUER_ID and AUTH_KEY_PATH in the environment.
"""
import json
import os
import sys
import time
import urllib.request
from datetime import datetime, timedelta, timezone

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com/v1"
MIN_AGE_HOURS = 3   # longer than any TestFlight run (45 min timeout)


def old_enough(cert):
    exp = cert["attributes"].get("expirationDate")
    if not exp:
        return False
    try:
        expires = datetime.fromisoformat(exp.replace("Z", "+00:00"))
    except ValueError:
        return False
    created = expires - timedelta(days=365)
    return datetime.now(timezone.utc) - created > timedelta(hours=MIN_AGE_HOURS)


def token():
    with open(os.environ["AUTH_KEY_PATH"]) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, url, tok):
    req = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {tok}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
        return json.loads(body) if body else None


def main():
    tok = token()
    certs, url = [], f"{API}/certificates?limit=200"
    while url:
        page = call("GET", url, tok)
        certs += page.get("data", [])
        url = page.get("links", {}).get("next")

    dev = [c for c in certs if c["attributes"].get("certificateType") in ("DEVELOPMENT", "IOS_DEVELOPMENT")]
    stale = [c for c in dev
             if "Created via API" in (c["attributes"].get("name") or "") + (c["attributes"].get("displayName") or "")
             and old_enough(c)]
    print(f"{len(dev)} development certificates, {len(stale)} made by CI runs over {MIN_AGE_HOURS}h ago")
    for c in stale:
        try:
            call("DELETE", f"{API}/certificates/{c['id']}", tok)
            print(f"Revoked one, expiring {c['attributes'].get('expirationDate', '?')[:10]}")
        except Exception as e:  # keep going; the archive step will say if it's still stuck
            print(f"Couldn't revoke one: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
