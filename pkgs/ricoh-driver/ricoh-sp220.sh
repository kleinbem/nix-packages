#!/usr/bin/env bash
set -euo pipefail

# CUPS backend for Ricoh SP 220Nw:
# Sanitizes options passed by CUPS/applications before delegating to the native IPP backend.
# no-link: Ricoh SP 220Nw is proprietary printer firmware with no public issue tracker or upstream repository
# The firmware rejects Validate-Job with client-error-attributes-or-values-not-supported
# when unrecognized vendor attributes (PageSize, ColorModel, finishings) are passed as job attributes,
# and redirects to the empty bypass tray if PageSize or media A4 creates rounded media-col dimensions.

if [ "$#" -eq 0 ]; then
  echo 'network ricoh-sp220 "Ricoh SP 220Nw" "Ricoh SP 220Nw Sanitizing IPP Backend"'
  exit 0
fi

CLEAN_OPTS="print-color-mode=monochrome"

read -r -a opts <<<"${5:-}"
for opt in "${opts[@]}"; do
  opt_lower="${opt,,}"
  case "$opt_lower" in
  pagesize=* | colormodel=* | finishings=* | print-color-mode=* | media=* | media-col=*)
    ;;
  *)
    CLEAN_OPTS="$CLEAN_OPTS $opt"
    ;;
  esac
done

REAL_URI="${DEVICE_URI#ricoh-sp220:}"
export DEVICE_URI="ipp:${REAL_URI}"

IPP_BACKEND="@cups@/lib/cups/backend/ipp"
if [ ! -x "$IPP_BACKEND" ]; then
  IPP_BACKEND="${CUPS_SERVERBIN:-/run/current-system/sw/lib/cups}/backend/ipp"
fi

if [ "$#" -ge 6 ]; then
  exec "$IPP_BACKEND" "$1" "$2" "$3" "$4" "$CLEAN_OPTS" "$6"
else
  exec "$IPP_BACKEND" "$1" "$2" "$3" "$4" "$CLEAN_OPTS"
fi
