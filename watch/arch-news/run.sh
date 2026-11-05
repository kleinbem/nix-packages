#!/usr/bin/env bash
# Prints the Arch Linux news items about the AUR (registration, accounts,
# aurweb, packages) published in the last DAYS days (default 3) as
# "title<TAB>link" lines, newest first, and exits 0.
# Reads the public news feed only: the AUR registration page asks not to be
# polled, and aur-general is behind a bot wall. FEED and MATCH override the
# source and the title filter.
set -euo pipefail

feed="${FEED:-https://archlinux.org/feeds/news/}"
match="${MATCH:-AUR|aurweb|[Rr]egistration|[Aa]ccount}"
days="${DAYS:-3}"

curl -fsS --retry 3 "$feed" | python3 -c '
import re, sys, xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
match = re.compile(sys.argv[1])
since = datetime.now(timezone.utc) - timedelta(days=int(sys.argv[2]))
for item in ET.parse(sys.stdin).getroot().iter("item"):
    title = (item.findtext("title") or "").strip()
    link = (item.findtext("link") or "").strip()
    published = parsedate_to_datetime(item.findtext("pubDate") or "")
    if published >= since and match.search(title):
        print(f"{title}\t{link}")
' "$match" "$days"
