#!/usr/bin/env bash
# Notarize + staple a signed DMG with notarytool (App Store Connect API key).
# Called by .github/workflows/hesper-remote-macos.yml; unit-tested by
# .github/scripts/test-macos-notarize.sh (stubbed xcrun, runs on any OS).
#
# Usage:  macos-notarize.sh <path/to/App.dmg>
#
# Required env (secrets are passed in by the workflow, never echoed here):
#   ASC_KEY_PATH     path to the decoded AuthKey .p8
#   ASC_KEY_ID       ASC API key id
#   ASC_ISSUER_ID    ASC issuer id
#
# Optional env (defaults are what CI uses; tests shrink them):
#   NOTARY_SUBMIT_TRIES=3          upload attempts before giving up
#   NOTARY_SUBMIT_SLEEP_SECONDS=20 pause between upload attempts
#   NOTARY_POLL_SECONDS=30         pause between status polls
#   NOTARY_TIMEOUT_SECONDS=1800    total time to wait for Apple's verdict
#   NOTARY_INFO_MAX_ERRORS=10      consecutive failed status polls tolerated
#   STAPLE_TRIES=6                 staple+validate attempts
#   STAPLE_SLEEP_SECONDS=30        pause between staple attempts
#
# Why submit-then-poll instead of `notarytool submit --wait`:
#   --wait holds one long connection and, if the network blips mid-wait
#   ("The network connection was lost"), it dies without us ever having
#   captured the submission id -- so a transient blip fails the whole build and
#   the next attempt has to re-upload. Capturing the id first lets us ride out
#   blips on the status poll, and bounds the wait with a hard deadline so a slow
#   Apple queue fails fast with the id to chase instead of burning the job
#   timeout.
set -euo pipefail

DMG="${1:?usage: macos-notarize.sh <path/to/App.dmg>}"
: "${ASC_KEY_PATH:?ASC_KEY_PATH not set}"
: "${ASC_KEY_ID:?ASC_KEY_ID not set}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID not set}"

SUBMIT_TRIES="${NOTARY_SUBMIT_TRIES:-3}"
SUBMIT_SLEEP="${NOTARY_SUBMIT_SLEEP_SECONDS:-20}"
POLL_SECONDS="${NOTARY_POLL_SECONDS:-30}"
TIMEOUT_SECONDS="${NOTARY_TIMEOUT_SECONDS:-1800}"
INFO_MAX_ERRORS="${NOTARY_INFO_MAX_ERRORS:-10}"
STAPLE_TRIES="${STAPLE_TRIES:-6}"
STAPLE_SLEEP="${STAPLE_SLEEP_SECONDS:-30}"

[ -f "$DMG" ] || { echo "::error::DMG not found: $DMG" >&2; exit 1; }

ERR_FILE="$(mktemp)"
trap 'rm -f "$ERR_FILE"' EXIT

AUTH=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")

# json_get <key>: print one top-level key from the first JSON object on stdin.
# Tolerates notarytool printing a progress line before the object.
json_get() {
  python3 -c '
import json, sys
s = sys.stdin.read()
i = s.find("{")
obj = json.JSONDecoder().raw_decode(s[i:])[0] if i >= 0 else {}
v = obj.get(sys.argv[1], "")
print("" if v is None else v)
' "$1"
}

# --- 1. upload (retried), capture the submission id -------------------------
SUB_ID=""
for ((i = 1; i <= SUBMIT_TRIES; i++)); do
  if out=$(xcrun notarytool submit "$DMG" "${AUTH[@]}" --output-format json 2>"$ERR_FILE"); then
    SUB_ID="$(printf '%s' "$out" | json_get id)"
    [ -n "$SUB_ID" ] && break
    echo "notarytool submit attempt $i/$SUBMIT_TRIES returned no submission id" >&2
  else
    echo "notarytool submit attempt $i/$SUBMIT_TRIES failed:" >&2
    cat "$ERR_FILE" >&2
  fi
  if ((i < SUBMIT_TRIES)); then sleep "$SUBMIT_SLEEP"; fi
done
if [ -z "$SUB_ID" ]; then
  echo "::error::notarytool submit failed after $SUBMIT_TRIES attempts (no submission id)"
  exit 1
fi
echo "::notice::Notarization submission id: $SUB_ID"

# --- 2. poll for Apple's verdict, bounded -----------------------------------
START=$(date +%s)
ERRORS=0
STATUS=""
while :; do
  if info=$(xcrun notarytool info "$SUB_ID" "${AUTH[@]}" --output-format json 2>"$ERR_FILE"); then
    ERRORS=0
    STATUS="$(printf '%s' "$info" | json_get status)"
    echo "[$(date -u +%H:%M:%S)] submission $SUB_ID: ${STATUS:-<empty>}"
    case "$STATUS" in
      Accepted) break ;;
      Invalid | Rejected)
        echo "::error::Apple notarization $STATUS for submission $SUB_ID -- notary log follows"
        xcrun notarytool log "$SUB_ID" "${AUTH[@]}" 2>&1 || true
        exit 1
        ;;
      *) : ;; # "In Progress" (or anything else non-terminal): keep polling
    esac
  else
    ERRORS=$((ERRORS + 1))
    echo "notarytool info failed ($ERRORS/$INFO_MAX_ERRORS consecutive; transient network?):" >&2
    cat "$ERR_FILE" >&2
    if ((ERRORS >= INFO_MAX_ERRORS)); then
      echo "::error::notarytool info failed $INFO_MAX_ERRORS times in a row for submission $SUB_ID"
      exit 1
    fi
  fi
  if (($(date +%s) - START >= TIMEOUT_SECONDS)); then
    echo "::error::Notarization still '${STATUS:-unknown}' after ${TIMEOUT_SECONDS}s for submission $SUB_ID (re-check with: xcrun notarytool info $SUB_ID)"
    exit 1
  fi
  sleep "$POLL_SECONDS"
done

# --- 3. staple + validate as a unit (CloudKit Error 68) ---------------------
# Stapler fetches the notarization ticket from Apple CloudKit and can hit a
# transient "network connection was lost" (NSURLErrorDomain -1005, Error 68)
# right after acceptance -- on BOTH staple AND validate. Retry the whole
# staple+validate as a unit with backoff, and fail only if every try fails.
ok=0
for ((i = 1; i <= STAPLE_TRIES; i++)); do
  if xcrun stapler staple "$DMG" && xcrun stapler validate "$DMG"; then
    ok=1
    break
  fi
  echo "staple/validate attempt $i/$STAPLE_TRIES failed (transient CloudKit ticket fetch?); retrying in ${STAPLE_SLEEP}s" >&2
  if ((i < STAPLE_TRIES)); then sleep "$STAPLE_SLEEP"; fi
done
[ "$ok" = 1 ] || {
  echo "::error::staple+validate failed after $STAPLE_TRIES attempts (submission $SUB_ID is Accepted; ticket fetch is the failing step)"
  exit 1
}

shasum -a 256 "$DMG" >"$DMG.sha256"
echo "Notarized + stapled: $DMG (submission $SUB_ID)"
