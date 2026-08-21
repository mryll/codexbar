#!/usr/bin/env bash
# Monochrome mode: --no-color[=all|bar|tooltip] and the NO_COLOR env var.
# "Plain" means no color markup on that surface — structure (glyphs, bar fill,
# markers, box drawing, font attributes, alignment) and the waybar `class`
# field are untouched, and the structured JSON is unaffected entirely.
source "$(dirname "$0")/lib.sh"

BASE=$(cat "$(dirname "$0")/fixtures/baseline.json")

# Hermetic runner: NO_COLOR is always set explicitly (or explicitly removed),
# so an ambient value in the caller's environment can never leak in.
# _nc_run <no-color-env|"unset"> [args...]
_nc_run() {
    local envval="$1"; shift
    local home; home="$(mktemp -d)" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    mkdir -p "$home/.codex" "$home/.cache/codexbar"
    local hdr acc idt
    hdr=$(printf '{"alg":"RS256"}' | _b64url)
    acc=$(printf '{"exp":4102444800}' | _b64url)
    idt=$(printf '{"https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}' | _b64url)
    jq -nc --arg at "$hdr.$acc.sig" --arg idt "$hdr.$idt.sig" \
        '{tokens:{access_token:$at,refresh_token:"x",account_id:"a",id_token:$idt}}' \
        > "$home/.codex/auth.json"
    printf '%s' "$BASE" > "$home/.cache/codexbar/usage.json"
    if [[ "$envval" == "unset" ]]; then
        OUT=$(env -u NO_COLOR HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$home/.cache" "$SCRIPT" "$@"); RC=$?
    else
        OUT=$(HOME="$home" NO_COLOR="$envval" XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$home/.cache" "$SCRIPT" "$@"); RC=$?
    fi
    rm -rf "$home"
}

_colors_in() { jq -r "$1" <<<"$OUT" | command grep -o "foreground=" | wc -l; }
_hex_in()    { jq -r "$1" <<<"$OUT" | command grep -coE '#[0-9a-fA-F]{6}' || true; }

# assert_surface <name> <jq-field> <colored|plain>
assert_surface() {
    local n="$1" field="$2" want="$3" got
    got=$(_colors_in "$field")
    if [[ "$want" == "plain" ]]; then
        if [[ "$got" -eq 0 && "$(_hex_in "$field")" -eq 0 ]]; then _ok "$n"
        else _no "$n" "expected no color markup, found $got foreground attrs / $(_hex_in "$field") hex"; fi
    else
        if [[ "$got" -gt 0 ]]; then _ok "$n"; else _no "$n" "expected color markup, found none"; fi
    fi
}

# --- The four states ---
_nc_run unset
assert_exit0     "default: exit 0"
assert_surface   "default: bar colored"     .text    colored
assert_surface   "default: tooltip colored" .tooltip colored

_nc_run unset --no-color
assert_exit0   "--no-color: exit 0"
assert_surface "--no-color: bar plain"     .text    plain
assert_surface "--no-color: tooltip plain" .tooltip plain

_nc_run unset --no-color=all
assert_surface "--no-color=all: bar plain"     .text    plain
assert_surface "--no-color=all: tooltip plain" .tooltip plain

_nc_run unset --no-color=bar
assert_surface "--no-color=bar: bar plain"       .text    plain
assert_surface "--no-color=bar: tooltip colored" .tooltip colored

_nc_run unset --no-color=tooltip
assert_surface "--no-color=tooltip: bar colored" .text    colored
assert_surface "--no-color=tooltip: tooltip plain" .tooltip plain

# --- NO_COLOR env (https://no-color.org) ---
_nc_run 1
assert_surface "NO_COLOR=1: bar plain"     .text    plain
assert_surface "NO_COLOR=1: tooltip plain" .tooltip plain
_nc_run "anything"
assert_surface "NO_COLOR=anything: plain"  .text    plain
# Empty value is NOT set, per the spec.
_nc_run ""
assert_surface "NO_COLOR empty: bar colored"     .text    colored
assert_surface "NO_COLOR empty: tooltip colored" .tooltip colored
# The explicit flag is the more specific instruction and wins.
_nc_run 1 --no-color=bar
assert_surface "NO_COLOR + --no-color=bar: bar plain"       .text    plain
assert_surface "NO_COLOR + --no-color=bar: tooltip colored" .tooltip colored
_nc_run 1 --no-color=tooltip
assert_surface "NO_COLOR + --no-color=tooltip: bar colored" .text    colored
assert_surface "NO_COLOR + --no-color=tooltip: tooltip plain" .tooltip plain

# --- Structure survives: class, glyphs, bars, markers, alignment ---
_nc_run unset --no-color
assert_class    "--no-color: class preserved" low
assert_text_has "--no-color: bar text intact" "46%"
assert_tip_has  "--no-color: window glyph kept"  "󰔟"
assert_tip_has  "--no-color: clock glyph kept"   "󰥔"
assert_tip_has  "--no-color: filled bar cells"   "█"
assert_tip_has  "--no-color: empty bar cells"    "░"
assert_tip_has  "--no-color: box drawing kept"   "─"
assert_tip_has  "--no-color: credits glyph kept" "󰄑"
command grep -qF "font_weight='bold'" <<<"$OUT" \
    && _ok "--no-color: font_weight kept" || _no "--no-color: font_weight kept" "bold attribute lost"
_nc_run unset --no-color --tooltip-pace-pts
assert_tip_has "--no-color: elapsed marker kept" "┃"
_nc_run unset --no-color --frame
assert_tip_has "--no-color: frame corner kept" "╭"
command grep -qF "font_family=" <<<"$OUT" \
    && _ok "--no-color: frame font pin kept" || _no "--no-color: frame font pin kept" "font_family lost"
_nc_run unset --no-color --icon '󰚩'
assert_text_has "--no-color: icon kept" "󰚩"

# --- Unknown value is an argument error (exit 0, right shape per mode) ---
_nc_run unset --no-color=bogus
assert_exit0      "bad value: exit 0"
assert_json_valid "bad value: valid JSON"
assert_class      "bad value: waybar error shape" critical
assert_tip_has    "bad value: message"  "--no-color must be all, bar, or tooltip"
_nc_run unset --json --no-color=bogus
assert_exit0      "bad value (json): exit 0"
assert_json_valid "bad value (json): valid JSON"
_j=$(jq -r '.error.message' <<<"$OUT")
[[ "$_j" == "--no-color must be all, bar, or tooltip" ]] \
    && _ok "bad value (json): structured error" || _no "bad value (json): structured error" "got: $_j"

# --- Structured JSON is untouched by the flag ---
# Two separate invocations legitimately disagree about anything derived from
# "now": updated_at is the cache file's mtime, and the reset stamps are
# now-plus-remaining, so they tick over if the runs straddle a second. Drop
# those; everything else must match byte for byte.
_norm() {
    jq -S 'del(.updated_at, .data_age_seconds)
           | walk(if type == "object" then del(.reset_at, .reset_at_unix) else . end)' <<<"$OUT"
}
_nc_run unset --json;            _json_plain=$(_norm)
_nc_run unset --json --no-color; _json_nc=$(_norm)
[[ "$_json_plain" == "$_json_nc" ]] \
    && _ok "json: identical with and without --no-color" \
    || _no "json: identical with and without --no-color" "$(diff <(printf '%s' "$_json_plain") <(printf '%s' "$_json_nc") | head -10)"
_nc_run 1 --json; _json_env=$(_norm)
[[ "$_json_plain" == "$_json_env" ]] \
    && _ok "json: unaffected by NO_COLOR env" \
    || _no "json: unaffected by NO_COLOR env" "differs"
_nc_run unset --json --no-color
[[ "$(jq -r '.palette.low' <<<"$OUT")" == "#98c379" ]] \
    && _ok "json: palette still published under --no-color" \
    || _no "json: palette still published under --no-color" "palette missing"

finish
