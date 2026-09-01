#!/usr/bin/env bash
# Transient network failure handling (boot robustness, adaptive deadline):
#  - boot-like start (old/missing/future-mtime cache) + no HTTP response
#      -> cached data + in-memory ⏸ (NO .stale on disk) + .net_wait episode marker
#  - sibling with a recent .net_wait -> exactly ONE attempt, no sleeps
#  - young cache (mid-session blip)  -> quick budget, no .net_wait
#  - transient failures retried until the deadline (curl recovers -> fresh data)
#  - hard HTTP failure (5xx)         -> .stale + .last_error persisted (regression)
#  - hard token-refresh failure      -> .last_error carries the provider message
source "$(dirname "$0")/lib.sh"

# Shrink the hidden budgets so the suite doesn't sleep for real.
export CODEXBAR_TEST_NET_QUICK_BUDGET=1
export CODEXBAR_TEST_NET_LONG_BUDGET=1
export CODEXBAR_TEST_NET_RETRY_DELAY=1

USAGE='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":42,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}}}'

# Custom harness: scriptable curl stub + controllable cache/.net_wait mtimes.
# Keeps $THOME alive for marker inspection; callers rm -rf it.
# _run_transient <curl-stub-body> <cache-spec: old|young|none|future> [nw-spec: now|future] [token: valid|expired]
_run_transient() {
    local stub="$1" cache_spec="$2" nw_spec="${3:-}" token_spec="${4:-valid}"
    THOME="$(mktemp -d)" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    mkdir -p "$THOME/.codex" "$THOME/.cache/codexbar" "$THOME/bin" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    printf '%s' "$stub" > "$THOME/bin/curl" && chmod +x "$THOME/bin/curl" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    printf '#!/usr/bin/env bash\nexit 0\n' > "$THOME/bin/notify-send" && chmod +x "$THOME/bin/notify-send"
    local hdr acc idt exp
    exp=4102444800                                  # year 2100 -> no refresh
    [[ "$token_spec" == "expired" ]] && exp=1000000000   # year 2001 -> refresh
    hdr=$(printf '{"alg":"RS256"}' | _b64url)
    acc=$(printf '{"exp":%s}' "$exp" | _b64url)
    idt=$(printf '{"https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}' | _b64url)
    jq -nc --arg at "$hdr.$acc.sig" --arg idt "$hdr.$idt.sig" \
        '{tokens:{access_token:$at,refresh_token:"x",account_id:"a",id_token:$idt}}' \
        > "$THOME/.codex/auth.json" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    local now; now=$(date +%s)
    case "$cache_spec" in
        old)    printf '%s' "$USAGE" > "$THOME/.cache/codexbar/usage.json"
                touch -d "@$(( now - 1200 ))" "$THOME/.cache/codexbar/usage.json" ;;
        young)  printf '%s' "$USAGE" > "$THOME/.cache/codexbar/usage.json"
                touch -d "@$(( now - 120 ))" "$THOME/.cache/codexbar/usage.json" ;;
        future) printf '%s' "$USAGE" > "$THOME/.cache/codexbar/usage.json"
                touch -d "@$(( now + 3600 ))" "$THOME/.cache/codexbar/usage.json" ;;
        none)   : ;;
    esac
    case "$nw_spec" in
        now)    touch "$THOME/.cache/codexbar/.net_wait" ;;
        future) touch -d "@$(( now + 3600 ))" "$THOME/.cache/codexbar/.net_wait" ;;
    esac
    # XDG dirs pinned inside the fake HOME: theme parsing needs no jq and no
    # network, so an ambient XDG_STATE_HOME would pull in the developer's real
    # Omarchy theme and make these runs machine-dependent.
    # PRE_RUN lets a caller plant something in the fake HOME after it is built
    # and before the script sees it (the FIFO tests). RUN_TIMEOUT wraps the run
    # so a blocking open fails its assertion instead of wedging the suite.
    [[ -n "${PRE_RUN:-}" ]] && eval "$PRE_RUN"
    local -a _to=()
    [[ -n "${RUN_TIMEOUT:-}" ]] && _to=(timeout "$RUN_TIMEOUT")
    OUT=$(HOME="$THOME" XDG_STATE_HOME="$THOME/.local/state" XDG_CACHE_HOME="$THOME/.cache" PATH="$THOME/bin:$PATH" "${_to[@]}" "$SCRIPT"); RC=$?
    return 0
}

curl_calls() { cat "$THOME/.curl_count" 2>/dev/null || echo 0; }
assert_no_stale()   { [[ ! -f "$THOME/.cache/codexbar/.stale" ]] && _ok "$1" || _no "$1" ".stale was written"; }
assert_net_wait()   { [[ -f "$THOME/.cache/codexbar/.net_wait" ]] && _ok "$1" || _no "$1" ".net_wait missing"; }
assert_no_net_wait(){ [[ ! -f "$THOME/.cache/codexbar/.net_wait" ]] && _ok "$1" || _no "$1" ".net_wait was written"; }

COUNT_FAIL_STUB='#!/usr/bin/env bash
cnt="$HOME/.curl_count"
n=$(( $(cat "$cnt" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$cnt"
exit 1
'

# --- Boot-like: old cache + always-fail -> long budget, ⏸ in memory, episode marked ---
_run_transient "$COUNT_FAIL_STUB" old
assert_exit0       "boot-like w/ cache: exit 0"
assert_json_valid  "boot-like w/ cache: valid JSON"
assert_text_has    "boot-like w/ cache: shows cached pct" "42%"
assert_text_has    "boot-like w/ cache: shows the pause mark" ""
assert_tip_has     "boot-like w/ cache: tooltip explains" "stale (waiting for network)"
assert_no_stale    "boot-like w/ cache: no .stale on disk"
assert_net_wait    "boot-like w/ cache: .net_wait episode marker written"
_c=$(curl_calls)
[[ "$_c" -ge 2 ]] && _ok "boot-like w/ cache: retried within budget (calls=$_c)" || _no "boot-like w/ cache: retried within budget" "calls=$_c"
rm -rf "$THOME"

# --- Boot-like: no cache + always-fail -> neutral Loading…, low class ---
_run_transient "$COUNT_FAIL_STUB" none
assert_exit0       "no cache: exit 0"
assert_json_valid  "no cache: valid JSON"
assert_text_has    "no cache: shows Loading…" "Loading…"
assert_class       "no cache: class low" low
assert_tip_has     "no cache: tooltip explains" "Waiting for network"
assert_no_stale    "no cache: no .stale on disk"
assert_net_wait    "no cache: .net_wait episode marker written"
rm -rf "$THOME"

# --- Sibling: recent .net_wait -> exactly one attempt, no sleeps ---
_run_transient "$COUNT_FAIL_STUB" old now
assert_exit0       "sibling w/ marker: exit 0"
assert_text_has    "sibling w/ marker: shows the pause mark" ""
assert_no_stale    "sibling w/ marker: no .stale on disk"
_c=$(curl_calls)
[[ "$_c" -eq 1 ]] && _ok "sibling w/ marker: exactly one attempt" || _no "sibling w/ marker: exactly one attempt" "calls=$_c"
rm -rf "$THOME"

# --- Future .net_wait mtime (clock skew) is ignored -> long budget again ---
_run_transient "$COUNT_FAIL_STUB" old future
assert_exit0       "future marker: exit 0"
_c=$(curl_calls)
[[ "$_c" -ge 2 ]] && _ok "future marker ignored: long budget used (calls=$_c)" || _no "future marker ignored: long budget used" "calls=$_c"
rm -rf "$THOME"

# --- Mid-session blip: young cache -> quick budget, NO episode marker ---
_run_transient "$COUNT_FAIL_STUB" young
assert_exit0       "young cache: exit 0"
assert_text_has    "young cache: shows the pause mark" ""
assert_no_stale    "young cache: no .stale on disk"
assert_no_net_wait "young cache: no .net_wait (quick budget)"
rm -rf "$THOME"

# --- Future cache mtime (clock skew) -> boot-like, data still shown ---
_run_transient "$COUNT_FAIL_STUB" future
assert_exit0       "future cache: exit 0"
assert_text_has    "future cache: shows cached pct" "42%"
assert_text_has    "future cache: shows the pause mark" ""
assert_net_wait    "future cache: treated as boot-like"
rm -rf "$THOME"

# --- Retry recovery: curl fails twice, succeeds on 3rd poll -> fresh data ---
# DELAY=0 is safe ONLY here: the stub succeeds by call count, so the loop
# terminates deterministically without spinning until the clock advances.
export CODEXBAR_TEST_NET_RETRY_DELAY=0
export CODEXBAR_TEST_NET_LONG_BUDGET=5
RETRY_STUB='#!/usr/bin/env bash
cnt="$HOME/.curl_count"
n=$(( $(cat "$cnt" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$cnt"
if (( n < 3 )); then exit 1; fi
printf "%s\n200" "{\"plan_type\":\"plus\",\"rate_limit\":{\"primary_window\":{\"used_percent\":77,\"reset_at\":9999999999,\"limit_window_seconds\":18000},\"secondary_window\":{\"used_percent\":10,\"reset_at\":9999999999,\"limit_window_seconds\":604800}}}"
'
_run_transient "$RETRY_STUB" old
assert_exit0       "retry recovers: exit 0"
assert_json_valid  "retry recovers: valid JSON"
assert_text_has    "retry recovers: fresh data after polls" "77%"
_c=$(curl_calls)
[[ "$_c" -eq 3 ]] && _ok "retry recovers: succeeded on 3rd poll" || _no "retry recovers: succeeded on 3rd poll" "calls=$_c"
assert_no_stale    "retry recovers: no .stale on disk"
assert_no_net_wait "retry recovers: no .net_wait after success"
rm -rf "$THOME"
export CODEXBAR_TEST_NET_RETRY_DELAY=1
export CODEXBAR_TEST_NET_LONG_BUDGET=1

# --- REGRESSION: hard HTTP failure (500) still persists .stale + .last_error ---
HARD_STUB='#!/usr/bin/env bash
printf "%s\n500" "{\"error\":{\"message\":\"boom\"}}"
'
_run_transient "$HARD_STUB" old
assert_exit0       "hard 500: exit 0"
assert_json_valid  "hard 500: valid JSON"
assert_text_has    "hard 500: shows cached pct" "42%"
assert_text_has    "hard 500: shows the pause mark" ""
assert_tip_has     "hard 500: tooltip explains" "stale (API errors)"
[[ -f "$THOME/.cache/codexbar/.stale" ]] && _ok "hard 500: .stale persisted" || _no "hard 500: .stale persisted" "marker missing"
[[ -f "$THOME/.cache/codexbar/.last_error" ]] && _ok "hard 500: .last_error written" || _no "hard 500: .last_error written" "file missing"
rm -rf "$THOME"

# --- Hard token-refresh failure (400) -> .last_error carries provider message ---
REFRESH_FAIL_STUB='#!/usr/bin/env bash
printf "%s\n400" "{\"error\":\"invalid_grant\"}"
'
_run_transient "$REFRESH_FAIL_STUB" old "" expired
assert_exit0       "hard refresh: exit 0"
assert_json_valid  "hard refresh: valid JSON"
assert_text_has    "hard refresh: shows cached pct" "42%"
assert_text_has    "hard refresh: shows the pause mark" ""
assert_tip_has     "hard refresh: tooltip explains" "stale (API errors)"
assert_tip_has     "hard refresh: tooltip shows HTTP code" "HTTP 400"
[[ -f "$THOME/.cache/codexbar/.stale" ]] && _ok "hard refresh: .stale persisted" || _no "hard refresh: .stale persisted" "marker missing"
grep -q "invalid_grant" "$THOME/.cache/codexbar/.last_error" 2>/dev/null \
    && _ok "hard refresh: .last_error carries provider message" \
    || _no "hard refresh: .last_error carries provider message" "$(cat "$THOME/.cache/codexbar/.last_error" 2>/dev/null || echo missing)"
rm -rf "$THOME"

# --- Every curl the script runs gets -q as its FIRST argument -----------------
# curl reads ~/.curlrc before the --config stream that carries the credentials,
# so without -q an attacker who can write that file redirects the token however
# they like and the escaping never sees it. -q anywhere but first is too late
# (test_hardening measures that against the real curl). An expired token drives
# BOTH network calls — the refresh and the usage fetch — so this covers both.
QSPY_STUB='#!/usr/bin/env bash
printf "%s\n" "$1" >> "$HOME/.qargs"
cnt="$HOME/.curl_count"
n=$(( $(cat "$cnt" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$cnt"
if [[ "$n" == 1 ]]; then
    printf "%s\n200" "{\"access_token\":\"h.p.s\",\"refresh_token\":\"r2\",\"id_token\":\"h.p.s\"}"
else
    printf "%s\n200" "{\"plan_type\":\"plus\",\"rate_limit\":{\"primary_window\":{\"used_percent\":42,\"reset_at\":9999999999,\"limit_window_seconds\":18000},\"secondary_window\":{\"used_percent\":10,\"reset_at\":9999999999,\"limit_window_seconds\":604800}}}"
fi
'
_run_transient "$QSPY_STUB" old "" expired
assert_exit0 "curl -q run: exit 0"
_q_calls=$(curl_calls)
[[ "$_q_calls" -ge 2 ]] \
    && _ok "curl -q run: both the refresh and the fetch fired (calls=$_q_calls)" \
    || _no "curl -q run: both the refresh and the fetch fired" "only $_q_calls call(s) — one of the two paths is untested"
_q_first=$(sort -u "$THOME/.qargs" 2>/dev/null | tr '\n' ',' || true)
[[ "$_q_first" == "-q," ]] \
    && _ok "every curl invocation starts with -q" \
    || _no "every curl invocation starts with -q" "first args seen: ${_q_first:-none}"
rm -rf "$THOME"

# --- A FIFO planted at .last_error must not freeze the widget -----------------
# The error path is the one a hostile server can trigger at will, and the path
# is predictable, so this is a write the attacker gets to aim. `> "$file"`
# blocks for ever on a FIFO; mktemp+rename never opens the destination at all.
# Guarded by RUN_TIMEOUT: a regression shows up as a red assertion, not a hung
# suite.
PRE_RUN='mkfifo "$THOME/.cache/codexbar/.last_error"' RUN_TIMEOUT=20 \
    _run_transient "$HARD_STUB" old
unset PRE_RUN RUN_TIMEOUT
[[ "$RC" -ne 124 ]] \
    && _ok "FIFO at .last_error: the run finishes instead of hanging" \
    || _no "FIFO at .last_error: the run finishes instead of hanging" "timed out (rc=124) — the write blocks"
assert_exit0      "FIFO at .last_error: exit 0"
assert_json_valid "FIFO at .last_error: valid JSON"
assert_text_has   "FIFO at .last_error: still shows cached pct" "42%"
[[ -f "$THOME/.cache/codexbar/.last_error" ]] \
    && _ok "FIFO at .last_error: replaced by a regular file" \
    || _no "FIFO at .last_error: replaced by a regular file" "still not a regular file"
# Read it only once it is known to be a regular file: a FIFO still sitting
# there blocks `grep` exactly as it blocked the widget, and a hung assertion
# reports nothing. This is the assertion that has to survive a regression.
_le_seen="(not a regular file)"
[[ -f "$THOME/.cache/codexbar/.last_error" ]] \
    && _le_seen=$(LC_ALL=C head -c 64 "$THOME/.cache/codexbar/.last_error" 2>/dev/null || true)
[[ "$_le_seen" == 500* ]] \
    && _ok "FIFO at .last_error: the real error was recorded" \
    || _no "FIFO at .last_error: the real error was recorded" "content: $_le_seen"
rm -rf "$THOME"

# --- Credentials rewrite: staged beside the target, lands in the FILE, and ----
# --- never tramples a concurrent CLI write ------------------------------------
# The temp is created in ~/.codex (same filesystem as auth.json, so the mv is
# rename(2), atomic) and BEFORE the POST (a 200 rotates the refresh token, so a
# refresh whose result cannot be persisted must never run). The curl stub
# observes the staging at POST time; the file is inspected afterwards.

REWRITE_STUB='#!/usr/bin/env bash
cnt="$HOME/.curl_count"
n=$(( $(cat "$cnt" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$cnt"
if [[ "$n" == 1 ]]; then
    ls "$HOME/.codex/".auth.?????? >> "$HOME/.stage_log" 2>/dev/null
    printf "%s\n200" "{\"access_token\":\"h.p.NEWAT\",\"refresh_token\":\"NEWRT\",\"id_token\":\"h.p.NEWIDT\"}"
else
    printf "%s\n200" "{\"plan_type\":\"plus\",\"rate_limit\":{\"primary_window\":{\"used_percent\":42,\"reset_at\":9999999999,\"limit_window_seconds\":18000},\"secondary_window\":{\"used_percent\":10,\"reset_at\":9999999999,\"limit_window_seconds\":604800}}}"
fi
'
_run_transient "$REWRITE_STUB" old "" expired
assert_exit0 "rewrite: exit 0"
[[ "$(jq -r '.tokens.access_token' "$THOME/.codex/auth.json")" == "h.p.NEWAT" ]] \
    && _ok "rewrite: the new access token is in the FILE" \
    || _no "rewrite: the new access token is in the FILE" "$(cat "$THOME/.codex/auth.json")"
[[ "$(jq -r '.tokens.refresh_token' "$THOME/.codex/auth.json")" == "NEWRT" ]] \
    && _ok "rewrite: the new refresh token is in the FILE" \
    || _no "rewrite: the new refresh token is in the FILE" "$(cat "$THOME/.codex/auth.json")"
grep -q . "$THOME/.stage_log" 2>/dev/null \
    && _ok "staging: the temp sits beside the target during the POST" \
    || _no "staging: the temp sits beside the target during the POST" "stage log empty"
compgen -G "$THOME/.codex/.auth.??????" >/dev/null \
    && _no "staging: no temp left behind" "$(ls -A "$THOME/.codex")" \
    || _ok "staging: no temp left behind"
rm -rf "$THOME"

# mktemp failing for the credentials temp: the token endpoint is never called
# (the refresh token is not consumed) and the stored file is byte-identical.
# The contract holds in both output modes.
ARGV_LOG_STUB='#!/usr/bin/env bash
printf "%s " "$@" >> "$HOME/.cargs"; echo >> "$HOME/.cargs"
cnt="$HOME/.curl_count"
n=$(( $(cat "$cnt" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$cnt"
printf "%s\n200" "{\"plan_type\":\"plus\",\"rate_limit\":{\"primary_window\":{\"used_percent\":42,\"reset_at\":9999999999,\"limit_window_seconds\":18000},\"secondary_window\":{\"used_percent\":10,\"reset_at\":9999999999,\"limit_window_seconds\":604800}}}"
'
PRE_RUN='cat > "$THOME/bin/mktemp" <<"EOS"
#!/usr/bin/env bash
for a in "$@"; do [[ "$a" == *.auth.* ]] && exit 1; done
exec /usr/bin/mktemp "$@"
EOS
chmod +x "$THOME/bin/mktemp"; cp "$THOME/.codex/auth.json" "$THOME/.auth_before"' \
    _run_transient "$ARGV_LOG_STUB" old "" expired
unset PRE_RUN
assert_exit0      "mktemp fail: exit 0"
assert_json_valid "mktemp fail: valid JSON"
grep -q 'oauth/token' "$THOME/.cargs" 2>/dev/null \
    && _no "mktemp fail: the token endpoint is never called" "argv: $(cat "$THOME/.cargs")" \
    || _ok "mktemp fail: the token endpoint is never called"
cmp -s "$THOME/.codex/auth.json" "$THOME/.auth_before" \
    && _ok "mktemp fail: the stored credentials are untouched" \
    || _no "mktemp fail: the stored credentials are untouched" "$(cat "$THOME/.codex/auth.json")"
OUT=$(HOME="$THOME" XDG_STATE_HOME="$THOME/.local/state" XDG_CACHE_HOME="$THOME/.cache" \
      PATH="$THOME/bin:$PATH" "$SCRIPT" --json); RC=$?
assert_exit0      "mktemp fail --json: exit 0"
assert_json_valid "mktemp fail --json: valid JSON"
rm -rf "$THOME"

# The CLI writes auth.json DURING the refresh POST: its write survives, ours
# is dropped (compare-before-write; the flock covers codexbar instances only).
CLI_CREDS='{"tokens":{"access_token":"h.p.CLIAT","refresh_token":"CLIRT","account_id":"a","id_token":"h.p.CLIIDT"}}'
CONCURRENT_STUB='#!/usr/bin/env bash
cnt="$HOME/.curl_count"
n=$(( $(cat "$cnt" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$cnt"
if [[ "$n" == 1 ]]; then
    printf "%s" '"'"'{"tokens":{"access_token":"h.p.CLIAT","refresh_token":"CLIRT","account_id":"a","id_token":"h.p.CLIIDT"}}'"'"' > "$HOME/.codex/auth.json"
    printf "%s\n200" "{\"access_token\":\"h.p.NEWAT\",\"refresh_token\":\"NEWRT\",\"id_token\":\"h.p.NEWIDT\"}"
else
    printf "%s\n200" "{\"plan_type\":\"plus\",\"rate_limit\":{\"primary_window\":{\"used_percent\":42,\"reset_at\":9999999999,\"limit_window_seconds\":18000},\"secondary_window\":{\"used_percent\":10,\"reset_at\":9999999999,\"limit_window_seconds\":604800}}}"
fi
'
_run_transient "$CONCURRENT_STUB" old "" expired
assert_exit0 "concurrent write: exit 0"
[[ "$(cat "$THOME/.codex/auth.json")" == "$CLI_CREDS" ]] \
    && _ok "concurrent write: the CLI's write survives" \
    || _no "concurrent write: the CLI's write survives" "$(cat "$THOME/.codex/auth.json")"
compgen -G "$THOME/.codex/.auth.??????" >/dev/null \
    && _no "concurrent write: no temp left behind" "$(ls -A "$THOME/.codex")" \
    || _ok "concurrent write: no temp left behind"
rm -rf "$THOME"

finish
