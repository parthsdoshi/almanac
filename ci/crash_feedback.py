"""Prints the newest TestFlight crash reports for the app, trimmed to what a fix needs.

Only the exception, the termination reason and the crashing thread's frames are printed,
because this repo's Actions logs are public. Tester comments, emails, device names and
IDs are never printed. Needs ASC_KEY_ID, ASC_ISSUER_ID, AUTH_KEY_PATH and APP_BUNDLE_ID.
"""
import json
import os
import re
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from revoke_ci_certs import API, token  # noqa: E402


def get(url, tok):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def trim(text):
    keep, out = False, []
    for line in text.splitlines():
        if re.match(r"^(Exception Type|Exception Codes|Exception Subtype|Termination Reason|Termination Description|Triggered by Thread|Crashed Thread|OS Version|Version|Application Specific Information)", line):
            out.append(line)
        if re.match(r"^Thread \d+ Crashed", line) or line.startswith("Last Exception Backtrace"):
            keep = True
            out.append(line)
            continue
        if keep:
            if not line.strip():
                keep = False
                out.append("")
                continue
            out.append(line)
    # Crash reports in JSON (.ips) form.
    if not out and text.lstrip().startswith("{"):
        out.append(text[:6000])
    return "\n".join(out)[:12000]


def main():
    tok = token()
    bid = os.environ["APP_BUNDLE_ID"]
    apps = get(f"{API}/apps?filter[bundleId]={urllib.parse.quote(bid)}", tok)["data"]
    if not apps:
        print("App not found"); return
    app = apps[0]["id"]
    subs = get(f"{API}/apps/{app}/betaFeedbackCrashSubmissions?sort=-createdDate&limit=3", tok).get("data", [])
    print(f"{len(subs)} crash submissions")
    for s in subs:
        a = s["attributes"]
        print(f"\n===== {a.get('createdDate')} {a.get('osVersion')} {a.get('deviceModel')} build {a.get('buildBundleId') or ''}")
        try:
            log = get(f"{API}/betaFeedbackCrashSubmissions/{s['id']}/crashLog", tok)["data"]["attributes"].get("logText") or ""
        except Exception as e:
            print(f"(no crash log: {e})"); continue
        print(trim(log))


if __name__ == "__main__":
    main()
