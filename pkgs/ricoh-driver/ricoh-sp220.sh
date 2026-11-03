#!/usr/bin/env bash
set -euo pipefail

# CUPS backend for Ricoh SP 220Nw:
# Sanitizes options passed by CUPS/applications before delegating to the native IPP backend.
# The Ricoh SP 220Nw IPP firmware rejects Validate-Job with client-error-attributes-or-values-not-supported
# when unrecognized vendor attributes (PageSize, ColorModel, finishings) are passed as job attributes,
# and redirects to the empty bypass tray if PageSize A4 creates rounded media-col dimensions.

if [ "$#" -eq 0 ]; then
  echo 'network ricoh-sp220 "Ricoh SP 220Nw" "Ricoh SP 220Nw Sanitizing IPP Backend"'
  exit 0
fi

ORIG_OPTS="${5:-}"
CLEAN_OPTS="print-color-mode=monochrome"

for opt in $ORIG_OPTS; do
  case "$opt" in
  PageSize=* | ColorModel=* | finishings=* | print-color-mode=*)
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
