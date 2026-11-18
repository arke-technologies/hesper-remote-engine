#!/usr/bin/env bash
# Unit test for macos-notarize.sh. Puts a fake `xcrun` first on PATH that
# replays scripted notarytool/stapler behaviour, so the retry / poll / timeout
# logic can be exercised on any OS without Apple credentials or network.
#
#   bash .github/scripts/test-macos-notarize.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/macos-notarize.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cat >"$WORK/bin/xcrun" <<'FAKE'
#!/usr/bin/env bash
# Fake xcrun. Scenario comes from $FAKE_SCENARIO; call counters live in $FAKE_STATE.
tick() { local f="$FAKE_STATE/$1"; local n=$(( $(cat "$f" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$f"; echo "$n"; }
case "$1 $2" in
  "notarytool submit")
    n=$(tick submit)
    case "$FAKE_SCENARIO" in
      submit_flaky) [ "$n" -lt 2 ] && { echo "Error: The network connection was lost." >&2; exit 1; } ;;
      submit_dead)  echo "Error: HTTP 401" >&2; exit 1 ;;
      submit_noid)  echo '{"message":"ok"}'; exit 0 ;;
    esac
    echo 'Progress 100%' ; echo '{"id":"sub-123","message":"Successfully uploaded file","path":"x.dmg"}' ;;
  "notarytool info")
    n=$(tick info)
    case "$FAKE_SCENARIO" in
      info_flaky)   [ "$n" -le 2 ] && { echo "Error: The network connection was lost." >&2; exit 1; } ; echo '{"id":"sub-123","status":"Accepted"}' ;;
      info_dead)    echo "Error: network down" >&2; exit 1 ;;
      invalid)      echo '{"id":"sub-123","status":"Invalid"}' ;;
      stuck)        echo '{"id":"sub-123","status":"In Progress"}' ;;
      *)            [ "$n" -lt 3 ] && echo '{"id":"sub-123","status":"In Progress"}' || echo '{"id":"sub-123","status":"Accepted"}' ;;
    esac ;;
  "notarytool log") echo '{"issues":[{"severity":"error","message":"fake: binary not signed"}]}' ;;
  "stapler staple")
    n=$(tick staple)
    case "$FAKE_SCENARIO" in
      staple_flaky) [ "$n" -lt 3 ] && { echo "Error 68: network connection was lost" >&2; exit 68; } ;;
      staple_dead)  exit 68 ;;
    esac
    exit 0 ;;
  "stapler validate")
    n=$(tick validate)
    case "$FAKE_SCENARIO" in
      validate_flaky) [ "$n" -lt 2 ] && { echo "Error 68" >&2; exit 68; } ;;
    esac
    exit 0 ;;
  *) echo "fake xcrun: unhandled: $*" >&2; exit 99 ;;
esac
FAKE
chmod +x "$WORK/bin/xcrun"

pass=0; fail=0
# run_case <name> <expected-rc> <scenario> [grep-pattern-expected-in-output] [extra env...]
run_case() {
  local name="$1" want_rc="$2" scenario="$3" pat="${4:-}"; shift 4 || shift $#
  local state="$WORK/state-$name"; mkdir -p "$state"
  local dmg="$WORK/$name.dmg"; echo "dmg" >"$dmg"; rm -f "$dmg.sha256"
  local out rc
  out=$(env PATH="$WORK/bin:$PATH" FAKE_SCENARIO="$scenario" FAKE_STATE="$state" \
        ASC_KEY_PATH=/dev/null ASC_KEY_ID=KEYID ASC_ISSUER_ID=ISSUER \
        NOTARY_SUBMIT_SLEEP_SECONDS=0 NOTARY_POLL_SECONDS=0 STAPLE_SLEEP_SECONDS=0 \
        "$@" bash "$SUT" "$dmg" 2>&1); rc=$?
  local ok=1
  [ "$rc" -eq "$want_rc" ] || ok=0
  if [ "$want_rc" -eq 0 ]; then [ -s "$dmg.sha256" ] || ok=0; else [ ! -e "$dmg.sha256" ] || ok=0; fi
  if [ -n "$pat" ]; then printf '%s' "$out" | grep -q -- "$pat" || ok=0; fi
  # Secrets must never be echoed.
  printf '%s' "$out" | grep -q -e KEYID -e ISSUER && { ok=0; echo "  !! key id / issuer leaked into output"; }
  if [ "$ok" = 1 ]; then echo "PASS  $name"; pass=$((pass+1))
  else echo "FAIL  $name (rc=$rc, wanted $want_rc, pattern '$pat')"; printf '%s\n' "$out" | sed 's/^/      | /'; fail=$((fail+1)); fi
}

run_case happy           0 happy           'Notarized + stapled'
run_case submit_flaky    0 submit_flaky    'submit attempt 1/3 failed'
run_case info_flaky      0 info_flaky      'notarytool info failed (2/'
run_case staple_flaky    0 staple_flaky    'staple/validate attempt 2/6 failed'
run_case validate_flaky  0 validate_flaky  'staple/validate attempt 1/6 failed'
run_case submit_dead     1 submit_dead     'failed after 3 attempts'
run_case submit_noid     1 submit_noid     'no submission id'
run_case invalid         1 invalid         'notary log follows'
run_case info_dead       1 info_dead       'failed 10 times in a row'
run_case staple_dead     1 staple_dead     'staple+validate failed after 6 attempts'
run_case stuck_times_out 1 stuck           'still .In Progress. after 1s' NOTARY_POLL_SECONDS=1 NOTARY_TIMEOUT_SECONDS=1

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
