#!/usr/bin/env bash
# Test harness for codexbar. Runs the real script against a crafted usage
# payload with NO network: fake $HOME, far-future token (no refresh), fresh cache.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/codexbar"
PASS=0; FAIL=0

_b64url() { base64 -w0 | tr '+/' '-_' | tr -d '='; }

# run_codexbar '<usage-json>' [args...]  -> prints script stdout; sets RC
run_codexbar() {
    local usage="$1"; shift
    local home; home="$(mktemp -d)" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    mkdir -p "$home/.codex" "$home/.cache/codexbar" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    local hdr acc idt
    hdr=$(printf '{"alg":"RS256"}' | _b64url)
    acc=$(printf '{"exp":4102444800}' | _b64url)            # year 2100 -> no refresh
    idt=$(printf '{"https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}' | _b64url)
    jq -nc --arg at "$hdr.$acc.sig" --arg idt "$hdr.$idt.sig" \
        '{tokens:{access_token:$at,refresh_token:"x",account_id:"a",id_token:$idt}}' \
        > "$home/.codex/auth.json" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    printf '%s' "$usage" > "$home/.cache/codexbar/usage.json" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    touch "$home/.cache/codexbar/usage.json"                 # fresh -> use cache, no fetch
    OUT=$(HOME="$home" "$SCRIPT" "$@"); RC=$?
    rm -rf "$home"
    return 0
}

# Like run_codexbar but with a caller-supplied auth.json, to exercise malformed
# credentials. Stubs `curl` to fail instantly (no token-refresh/fetch touches the
# network); the fresh cache supplies the output.
# run_codexbar_auth '<auth-json>' '<usage-json>' [args...]
run_codexbar_auth() {
    local auth="$1" usage="$2"; shift 2
    local home; home="$(mktemp -d)" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    mkdir -p "$home/.codex" "$home/.cache/codexbar" "$home/bin" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    printf '#!/usr/bin/env bash\nexit 1\n' > "$home/bin/curl" && chmod +x "$home/bin/curl" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    printf '%s' "$auth"  > "$home/.codex/auth.json"          || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    printf '%s' "$usage" > "$home/.cache/codexbar/usage.json" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    touch "$home/.cache/codexbar/usage.json"
    OUT=$(HOME="$home" PATH="$home/bin:$PATH" "$SCRIPT" "$@"); RC=$?
    rm -rf "$home"
    return 0
}

_ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
_no()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n    %s\n' "$1" "${2:-}"; }

assert_exit0()      { [[ "$RC" -eq 0 ]] && _ok "$1" || _no "$1" "exit=$RC"; }
assert_json_valid() { jq -e . >/dev/null 2>&1 <<<"$OUT" && _ok "$1" || _no "$1" "invalid JSON: $OUT"; }
assert_class()      { local c; c=$(jq -r .class <<<"$OUT"); [[ "$c" == "$2" ]] && _ok "$1" || _no "$1" "class=$c want=$2"; }
# strip pango tags before substring checks
_plain() { jq -r "$1" <<<"$OUT" | sed 's/<[^>]*>//g'; }
assert_text_has()    { _plain .text    | grep -qF -- "$2" && _ok "$1" || _no "$1" "text lacks: $2"; }
assert_tip_has()     { _plain .tooltip | grep -qF -- "$2" && _ok "$1" || _no "$1" "tooltip lacks: $2"; }
assert_tip_lacks()   { _plain .tooltip | grep -qF -- "$2" && _no "$1" "tooltip has: $2" || _ok "$1"; }

finish() { printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"; [[ "$FAIL" -eq 0 ]]; }
