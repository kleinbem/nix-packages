#!/usr/bin/env bash
set -euo pipefail

# CUPS backend for Ricoh SP 220Nw:
# Sanitizes options passed by CUPS/applications before delegating to the native IPP backend,
# clears any ghost jobs wedged in printer memory, and bounds transmission time.
# no-link: Ricoh SP 220Nw is proprietary printer firmware with no public issue tracker or upstream repository
# The firmware rejects Validate-Job with client-error-attributes-or-values-not-supported
# when unrecognized vendor attributes (PageSize, ColorModel, finishings) are passed as job attributes,
# redirects to the empty bypass tray if PageSize or media A4 creates rounded media-col dimensions,
# and permanently wedges the print engine in 'processing' if an earlier job is interrupted or aborted.

if [ "$#" -eq 0 ]; then
  echo 'network ricoh-sp220 "Ricoh SP 220Nw" "Ricoh SP 220Nw Sanitizing IPP Backend"'
  exit 0
fi

# Allowlist only valid user print-intent options, discarding CUPS queue internals
# (e.g. printer-state=*, marker-*, device-uri=*) and firmware-conflicting options
# (PageSize, ColorModel, finishings, media, media-col).
CLEAN_OPTS="print-color-mode=monochrome"

read -r -a opts <<<"${5:-}"
for opt in "${opts[@]}"; do
  opt_lower="${opt,,}"
  case "$opt_lower" in
  copies=* | number-up=* | orientation-requested=* | page-ranges=* | resolution=* | sides=* | job-priority=* | job-hold-until=* | collate | nocollate)
    CLEAN_OPTS="$CLEAN_OPTS $opt"
    ;;
  *)
    ;;
  esac
done

REAL_URI="${DEVICE_URI#ricoh-sp220:}"
export DEVICE_URI="ipp:${REAL_URI}"
TARGET_URI="ipp:${REAL_URI%%\?*}"

# Pre-flight: cancel any leftover stuck/ghost jobs in the Ricoh controller from prior sessions.
IPPTOOL="@cups@/bin/ipptool"
CANCEL_TEST="@cups@/share/cups/ipptool/cancel-current-job.test"
if [ -x "$IPPTOOL" ] && [ -f "$CANCEL_TEST" ]; then
  "$IPPTOOL" -q -V 1.0 -T 3 "$TARGET_URI" "$CANCEL_TEST" >/dev/null 2>&1 || true
fi

IPP_BACKEND="@cups@/lib/cups/backend/ipp"
if [ ! -x "$IPP_BACKEND" ]; then
  IPP_BACKEND="${CUPS_SERVERBIN:-/run/current-system/sw/lib/cups}/backend/ipp"
fi

TIMEOUT_BIN="@coreutils@/bin/timeout"
TIMEOUT_CMD=()
if [ -x "$TIMEOUT_BIN" ]; then
  # 180s transmission watchdog: abort cleanly if the printer stops receiving bytes
  TIMEOUT_CMD=("$TIMEOUT_BIN" "--kill-after=10s" "180s")
fi

if [ "$#" -ge 6 ]; then
  exec "${TIMEOUT_CMD[@]}" "$IPP_BACKEND" "$1" "$2" "$3" "$4" "$CLEAN_OPTS" "$6"
else
  exec "${TIMEOUT_CMD[@]}" "$IPP_BACKEND" "$1" "$2" "$3" "$4" "$CLEAN_OPTS"
fi
