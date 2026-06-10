#!/usr/bin/env bash
# Transient network failure handling (boot robustness):
#  - no HTTP response + usable cache -> cached data + in-memory ⏸, NO .stale on disk
#  - no HTTP response + no cache     -> neutral "Loading…", class low
#  - transient failures are retried within one dispatch (curl recovers -> fresh data)
#  - hard HTTP failure (5xx)         -> .stale marker on disk (regression)
source "$(dirname "$0")/lib.sh"

USAGE='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":42,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}}}'

# Custom harness: STALE cache (forces a fetch) + scriptable curl stub.
# Keeps $THOME alive for marker inspection; callers rm -rf it.
# _run_transient <curl-stub-body> [no-cache]
_run_transient() {
    local stub="$1" no_cache="${2:-}"
    THOME="$(mktemp -d)" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    mkdir -p "$THOME/.codex" "$THOME/.cache/codexbar" "$THOME/bin" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    printf '%s' "$stub" > "$THOME/bin/curl" && chmod +x "$THOME/bin/curl" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    local hdr acc idt
    hdr=$(printf '{"alg":"RS256"}' | _b64url)
    acc=$(printf '{"exp":4102444800}' | _b64url)            # year 2100 -> no refresh
    idt=$(printf '{"https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}' | _b64url)
    jq -nc --arg at "$hdr.$acc.sig" --arg idt "$hdr.$idt.sig" \
        '{tokens:{access_token:$at,refresh_token:"x",account_id:"a",id_token:$idt}}' \
        > "$THOME/.codex/auth.json" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    if [[ -z "$no_cache" ]]; then
        printf '%s' "$USAGE" > "$THOME/.cache/codexbar/usage.json" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
        touch -d '10 minutes ago' "$THOME/.cache/codexbar/usage.json"
    fi
    OUT=$(HOME="$THOME" PATH="$THOME/bin:$PATH" "$SCRIPT"); RC=$?
    return 0
}

assert_no_stale_marker() {
    [[ ! -f "$THOME/.cache/codexbar/.stale" ]] && _ok "$1" || _no "$1" ".stale was written to disk"
}

FAIL_STUB=$'#!/usr/bin/env bash\nexit 1\n'

# --- Transient failure + usable cache: cached data, ⏸ in memory only ---
_run_transient "$FAIL_STUB"
assert_exit0       "transient w/ cache: exit 0"
assert_json_valid  "transient w/ cache: valid JSON"
assert_text_has    "transient w/ cache: shows cached pct" "42%"
assert_text_has    "transient w/ cache: shows ⏸" "⏸"
assert_no_stale_marker "transient w/ cache: no .stale on disk"
rm -rf "$THOME"

# --- Transient failure + no cache: neutral Loading…, low class ---
_run_transient "$FAIL_STUB" no-cache
assert_exit0       "transient no cache: exit 0"
assert_json_valid  "transient no cache: valid JSON"
assert_text_has    "transient no cache: shows Loading…" "Loading…"
assert_class       "transient no cache: class low" low
assert_no_stale_marker "transient no cache: no .stale on disk"
rm -rf "$THOME"

# --- Retry: curl fails twice, succeeds on 3rd attempt -> fresh data, no ⏸ ---
RETRY_STUB='#!/usr/bin/env bash
cnt="$HOME/.curl_count"
n=$(( $(cat "$cnt" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$cnt"
if (( n < 3 )); then exit 1; fi
printf "%s\n200" "{\"plan_type\":\"plus\",\"rate_limit\":{\"primary_window\":{\"used_percent\":77,\"reset_at\":9999999999,\"limit_window_seconds\":18000},\"secondary_window\":{\"used_percent\":10,\"reset_at\":9999999999,\"limit_window_seconds\":604800}}}"
'
_run_transient "$RETRY_STUB"
assert_exit0       "retry recovers: exit 0"
assert_json_valid  "retry recovers: valid JSON"
assert_text_has    "retry recovers: fresh data after retries" "77%"
_calls=$(cat "$THOME/.curl_count" 2>/dev/null || echo 0)
[[ "$_calls" -eq 3 ]] && _ok "retry recovers: curl attempted 3 times" || _no "retry recovers: curl attempted 3 times" "calls=$_calls"
assert_no_stale_marker "retry recovers: no .stale on disk"
rm -rf "$THOME"

# --- REGRESSION: hard HTTP failure (500) still writes .stale + .last_error ---
HARD_STUB='#!/usr/bin/env bash
printf "%s\n500" "{\"error\":{\"message\":\"boom\"}}"
'
_run_transient "$HARD_STUB"
assert_exit0       "hard 500 w/ cache: exit 0"
assert_json_valid  "hard 500 w/ cache: valid JSON"
assert_text_has    "hard 500 w/ cache: shows cached pct" "42%"
assert_text_has    "hard 500 w/ cache: shows ⏸" "⏸"
[[ -f "$THOME/.cache/codexbar/.stale" ]] && _ok "hard 500: .stale persisted" || _no "hard 500: .stale persisted" "marker missing"
[[ -f "$THOME/.cache/codexbar/.last_error" ]] && _ok "hard 500: .last_error written" || _no "hard 500: .last_error written" "file missing"
rm -rf "$THOME"

finish
