#!/usr/bin/env bash
# Structured JSON output mode (--json): raw data for non-waybar frontends
# (e.g. the Omarchy shell plugin). Also covers --refresh (cache bypass),
# arg errors in JSON mode, control-char escaping, and the jq-less fallback.
source "$(dirname "$0")/lib.sh"

# Shrink the hidden network budgets so the --refresh test doesn't sleep for real.
export CODEXBAR_TEST_NET_QUICK_BUDGET=0
export CODEXBAR_TEST_NET_LONG_BUDGET=0
export CODEXBAR_TEST_NET_RETRY_DELAY=0

# assert_jq <name> <jq-filter> <expected>
assert_jq() {
    local got; got=$(jq -r "$2" <<<"$OUT" 2>/dev/null)
    [[ "$got" == "$3" ]] && _ok "$1" || _no "$1" "jq '$2' = $got, want $3"
}

BASE=$(cat "$(dirname "$0")/fixtures/baseline.json")
PROLITE=$(cat "$(dirname "$0")/fixtures/usage-prolite-spark.json")

# --- Baseline fixture: session + weekly + review + credits ---
run_codexbar "$BASE" --json
assert_exit0      "json: exit 0"
assert_json_valid "json: valid JSON"
assert_jq "json: schema_version 2"        '.schema_version'  "2"
assert_jq "json: error null"              '.error'           "null"
assert_jq "json: loading false"           '.loading'         "false"
assert_jq "json: plan label"              '.plan'            "Plus"
assert_jq "json: overall state low"       '.state'           "low"
assert_jq "json: three windows"           '.windows | length' "3"
assert_jq "json: session used_pct"        '.windows[0].used_pct'      "46"
assert_jq "json: session remaining_pct"   '.windows[0].remaining_pct' "54"
assert_jq "json: session window seconds"  '.windows[0].window_seconds' "18000"
assert_jq "json: session state low"       '.windows[0].state'          "low"
assert_jq "json: used_pct is number"      '.windows[0].used_pct | type' "number"
assert_jq "json: reset_at ISO-8601"       '.windows[0].reset_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "true"
assert_jq "json: session pace has delta"  '.windows[0].pace.delta_points | type' "number"
# Four bands now, the same ones claudebar publishes: a delta of +10 or more
# is "hot", not merely "ahead".
assert_jq "json: session pace state"      '.windows[0].pace.state'     "hot"
assert_jq "json: session pace indicator"  '.windows[0].pace.indicator' "↑"
assert_jq "json: max_pct present"         '.max_pct | type'            "number"
assert_jq "json: weekly id + pct"         '.windows[1] | "\(.id) \(.used_pct)"' "weekly 47"
assert_jq "json: review id + pct"         '.windows[2] | "\(.id) \(.used_pct) \(.label)"' "review 4 Code review"
assert_jq "json: elapsed_pct present"     '.windows[0].elapsed_pct | type' "number"
assert_jq "json: credits balance number"  '.credits.balance'           "12"
assert_jq "json: balance is number"       '.credits.balance | type'    "number"
assert_jq "json: credits has_credits"     '.credits.has_credits'       "true"
assert_jq "json: credits local range"     '.credits.approx_local_messages | join("-")' "10-20"
assert_jq "json: stale false"             '.stale'           "false"
assert_jq "json: updated_at set"          '.updated_at != null' "true"
grep -qF '<span' <<<"$OUT" && _no "json: no pango markup" "found <span" || _ok "json: no pango markup"
grep -qF '█' <<<"$OUT" && _no "json: no ascii bars" "found bar glyph" || _ok "json: no ascii bars"

# --- Gauge palette: the four resolved severity anchors ---
# The Omarchy panel builds its gauge ramp from these, so both frontends share
# one palette definition and the same --color-* overrides.
run_codexbar "$BASE" --json
assert_jq "palette: present"            '.palette | type'        "object"
assert_jq "palette: four anchors"       '.palette | keys_unsorted | map(select(. != "stops")) | join(",")' "low,mid,high,critical"
assert_jq "palette: all #RRGGBB"        '[.palette | del(.stops) | .[] | test("^#[0-9a-fA-F]{6}$")] | all' "true"
# No theme file in the harness HOME -> One Dark defaults.
assert_jq "palette: default low green"     '.palette.low'      "#98c379"
assert_jq "palette: default mid yellow"    '.palette.mid'      "#e5c07b"
assert_jq "palette: default high orange"   '.palette.high'     "#d19a66"
assert_jq "palette: default critical red"  '.palette.critical' "#e06c75"

# The ramp's stop POSITIONS are published too, so the panel never re-derives
# thresholds. These assertions tie the published stops to the severity classes:
# if a threshold moves in the core, both must move together or this fails.
run_codexbar "$BASE" --json
assert_jq "stops: published"            '.palette.stops | type'   "array"
assert_jq "stops: five anchors"         '.palette.stops | length' "5"
assert_jq "stops: ascending, 0..100"    '[.palette.stops[].pct] | (. == (.|sort)) and (.[0] == 0) and (.[-1] == 100)' "true"
assert_jq "stops: colors are #RRGGBB"   '[.palette.stops[].color | test("^#[0-9a-fA-F]{6}$")] | all' "true"
assert_jq "stops: anchors match keys"   '[.palette.stops[0].color == .palette.low, .palette.stops[-1].color == .palette.critical] | all' "true"

# Each interior stop must be the first percent of its band, per severity_for.
_mid_at=$(jq -r '.palette.stops[1].pct' <<<"$OUT")
_high_at=$(jq -r '.palette.stops[2].pct' <<<"$OUT")
_crit_at=$(jq -r '.palette.stops[3].pct' <<<"$OUT")
_state_at() {
    run_codexbar "{\"plan_type\":\"plus\",\"rate_limit\":{\"primary_window\":{\"used_percent\":$1,\"reset_at\":9999999999,\"limit_window_seconds\":18000}}}" --json
    jq -r '.windows[0].state' <<<"$OUT"
}
for _probe in "$(( _mid_at - 1 )):low" "$_mid_at:mid" "$(( _high_at - 1 )):mid" \
              "$_high_at:high" "$(( _crit_at - 1 )):high" "$_crit_at:critical" "100:critical"; do
    _pct=${_probe%%:*}; _want=${_probe##*:}; _got=$(_state_at "$_pct")
    [[ "$_got" == "$_want" ]] && _ok "stop boundary ${_pct}% -> $_want" \
                              || _no "stop boundary ${_pct}% -> $_want" "got $_got"
done

run_codexbar "$BASE" --json --color-low '#50fa7b' --color-critical '#ff5555'
assert_jq "palette: --color-low honored"      '.palette.low'      "#50fa7b"
assert_jq "palette: --color-critical honored" '.palette.critical' "#ff5555"
assert_jq "palette: untouched anchors keep defaults" '.palette.mid' "#e5c07b"

# --- Theme resolution: state path + named color keys ---
# Omarchy moved the active theme under ~/.local/state; themes name their
# colors (green/yellow/orange/red) rather than colorN.
_theme_run() {  # <theme-toml> <relative-theme-dir>
    local toml="$1" dir="$2"; shift 2
    local home; home="$(mktemp -d)" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    mkdir -p "$home/.codex" "$home/.cache/codexbar" "$home/$dir"
    local hdr acc idt
    hdr=$(printf '{"alg":"RS256"}' | _b64url)
    acc=$(printf '{"exp":4102444800}' | _b64url)
    idt=$(printf '{"https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}' | _b64url)
    jq -nc --arg at "$hdr.$acc.sig" --arg idt "$hdr.$idt.sig" \
        '{tokens:{access_token:$at,refresh_token:"x",account_id:"a",id_token:$idt}}' \
        > "$home/.codex/auth.json"
    printf '%s' "$BASE" > "$home/.cache/codexbar/usage.json"
    printf '%s' "$toml" > "$home/$dir/colors.toml"
    OUT=$(HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$home/.cache" "$SCRIPT" "$@"); RC=$?
    rm -rf "$home"
}

NAMED_THEME='green = "#9ece6a"
yellow = "#e0af68"
orange = "#eb927b"
red = "#f7768e"
foreground = "#a9b1d6"
background = "#1a1b26"'

_theme_run "$NAMED_THEME" ".local/state/omarchy/current/theme" --json
assert_jq "theme(state path): named green"  '.palette.low'      "#9ece6a"
assert_jq "theme(state path): named yellow" '.palette.mid'      "#e0af68"
assert_jq "theme(state path): named orange" '.palette.high'     "#eb927b"
assert_jq "theme(state path): named red"    '.palette.critical' "#f7768e"

# Legacy ~/.config location still works for older installs.
_theme_run "$NAMED_THEME" ".config/omarchy/current/theme" --json
assert_jq "theme(legacy path): still read" '.palette.low' "#9ece6a"

# colorN themes keep working; named keys win when both are present.
COLORN_THEME='color1 = "#ff0000"
color2 = "#00ff00"
color3 = "#ffff00"'
_theme_run "$COLORN_THEME" ".local/state/omarchy/current/theme" --json
assert_jq "theme(colorN): color2 -> low"       '.palette.low'      "#00ff00"
assert_jq "theme(colorN): color3 -> mid"       '.palette.mid'      "#ffff00"
assert_jq "theme(colorN): color1 -> critical"  '.palette.critical' "#ff0000"

# CLI flags still outrank the theme.
_theme_run "$NAMED_THEME" ".local/state/omarchy/current/theme" --json --color-low '#123456'
assert_jq "theme: --color-low outranks theme" '.palette.low'      "#123456"
assert_jq "theme: other anchors still themed" '.palette.critical' "#f7768e"

# --- Theme robustness: XDG_STATE_HOME, per-key validation, hostile values ---
# _xdg_theme_run <theme-toml> <where: xdg|home|legacy> <xdg-state-value> [args...]
_xdg_theme_run() {
    local toml="$1" where="$2" xdgval="$3"; shift 3
    local home; home="$(mktemp -d)" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    mkdir -p "$home/.codex" "$home/.cache/codexbar"
    local hdr acc
    hdr=$(printf '{"alg":"RS256"}' | _b64url)
    acc=$(printf '{"exp":4102444800}' | _b64url)
    jq -nc --arg at "$hdr.$acc.sig" \
        '{tokens:{access_token:$at,refresh_token:"x",account_id:"a"}}' > "$home/.codex/auth.json"
    printf '%s' "$BASE" > "$home/.cache/codexbar/usage.json"
    local dir
    case "$where" in
        xdg)    dir="$home/xdgstate/omarchy/current/theme" ;;
        home)   dir="$home/.local/state/omarchy/current/theme" ;;
        legacy) dir="$home/.config/omarchy/current/theme" ;;
    esac
    mkdir -p "$dir"; printf '%s\n' "$toml" > "$dir/colors.toml"
    # The value under test is passed verbatim, including the empty string.
    OUT=$(HOME="$home" XDG_STATE_HOME="$xdgval" XDG_CACHE_HOME="$home/.cache" "$SCRIPT" "$@" 2>/dev/null)
    ERR=$(HOME="$home" XDG_STATE_HOME="$xdgval" XDG_CACHE_HOME="$home/.cache" "$SCRIPT" "$@" 2>&1 >/dev/null)
    RC=$?
    rm -rf "$home"
}

# XDG_STATE_HOME pointing somewhere without a theme finds nothing.
_empty_state="$(mktemp -d)"
_xdg_theme_run 'green = "#00ff00"' xdg "$_empty_state" --json
assert_jq "XDG_STATE_HOME without a theme: built-in defaults" '.palette.low' "#98c379"
rm -rf "$_empty_state"

# Proper XDG_STATE_HOME run: build the home first so the path can be passed in.
_home_for_xdg="$(mktemp -d)"
mkdir -p "$_home_for_xdg/.codex" "$_home_for_xdg/.cache/codexbar" "$_home_for_xdg/xdgstate/omarchy/current/theme"
_hdr=$(printf '{"alg":"RS256"}' | _b64url); _acc=$(printf '{"exp":4102444800}' | _b64url)
jq -nc --arg at "$_hdr.$_acc.sig" '{tokens:{access_token:$at,refresh_token:"x",account_id:"a"}}' \
    > "$_home_for_xdg/.codex/auth.json"
printf '%s' "$BASE" > "$_home_for_xdg/.cache/codexbar/usage.json"
printf 'green = "#00ff00"\n' > "$_home_for_xdg/xdgstate/omarchy/current/theme/colors.toml"
OUT=$(HOME="$_home_for_xdg" XDG_STATE_HOME="$_home_for_xdg/xdgstate" XDG_CACHE_HOME="$_home_for_xdg/.cache" "$SCRIPT" --json)
assert_jq "XDG_STATE_HOME honored" '.palette.low' "#00ff00"
# Empty XDG_STATE_HOME means unset, not "relative to cwd".
mkdir -p "$_home_for_xdg/.local/state/omarchy/current/theme"
printf 'green = "#0000ff"\n' > "$_home_for_xdg/.local/state/omarchy/current/theme/colors.toml"
OUT=$(HOME="$_home_for_xdg" XDG_STATE_HOME="" XDG_CACHE_HOME="$_home_for_xdg/.cache" "$SCRIPT" --json)
assert_jq "empty XDG_STATE_HOME falls back to ~/.local/state" '.palette.low' "#0000ff"
rm -rf "$_home_for_xdg"

# A malformed theme must not abort, must not emit shell noise, and must keep
# per-key defaults rather than poisoning the palette.
_xdg_theme_run 'foreground = "not-a-hex"
background = "#1a1b26"
green = "#00ff00"' home "" --json
assert_exit0      "malformed theme: exit 0"
assert_json_valid "malformed theme: valid JSON"
assert_jq "malformed theme: valid key still used"  '.palette.low' "#00ff00"
[[ -z "$ERR" ]] && _ok "malformed theme: no stderr noise" \
                || _no "malformed theme: no stderr noise" "stderr: $ERR"

# A theme value that would break out of a Pango attribute is rejected outright.
_xdg_theme_run "green = \"#fff' foreground='#ff0000\"" home "" --json
assert_jq "hostile theme value rejected" '.palette.low' "#98c379"
_xdg_theme_run "green = \"#fff' foreground='#ff0000\"" home ""
assert_json_valid "hostile theme value: waybar output still valid"
command grep -qF "foreground='#ff0000'" <<<"$OUT" \
    && _no "hostile theme value not injected into Pango" "injected!" \
    || _ok "hostile theme value not injected into Pango"

# Invalid semantic key must not suppress the valid legacy alias.
_xdg_theme_run 'color2 = "#010203"
green = "nonsense"' home "" --json
assert_jq "invalid semantic key falls back to legacy alias" '.palette.low' "#010203"

# Legacy ~/.config location still works when the state dir has no theme.
_xdg_theme_run 'green = "#040506"' legacy "" --json
assert_jq "legacy config path still read" '.palette.low' "#040506"

# --- pywal fallback: used only when no Omarchy theme exists ---
# Hermetic: every run gets its own HOME *and* an explicit XDG_CACHE_HOME, so an
# ambient XDG_CACHE_HOME from the caller's environment can't leak in.
WAL='{"special":{"background":"#0f1419","foreground":"#e6e1cf","cursor":"#f29718"},
      "colors":{"color0":"#0f1419","color1":"#ff3333","color2":"#b8cc52",
                "color3":"#e7c547","color4":"#36a3d9"}}'

# _wal_run <wal-json|""> <theme-toml|""> <xdg-mode: home|custom> [args...]
_wal_run() {
    local wal="$1" toml="$2" xdg_mode="$3"; shift 3
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
    [[ -n "$toml" ]] && {
        mkdir -p "$home/.local/state/omarchy/current/theme"
        printf '%s\n' "$toml" > "$home/.local/state/omarchy/current/theme/colors.toml"
    }
    local cache_root="$home/.cache"
    [[ "$xdg_mode" == "custom" ]] && cache_root="$home/xdgcache"
    [[ -n "$wal" ]] && { mkdir -p "$cache_root/wal"; printf '%s' "$wal" > "$cache_root/wal/colors.json"; }
    OUT=$(HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$cache_root" "$SCRIPT" "$@"); RC=$?
    rm -rf "$home"
}

_wal_run "$WAL" "" home --json
assert_exit0 "pywal: exit 0"
assert_jq "pywal: color2 -> low"       '.palette.low'      "#b8cc52"
assert_jq "pywal: color3 -> mid"       '.palette.mid'      "#e7c547"
assert_jq "pywal: color1 -> critical"  '.palette.critical' "#ff3333"
# No pywal orange slot: midpoint of yellow and red keeps four distinct steps.
assert_jq "pywal: orange synthesized"  '.palette.high'     "#f37c3d"
assert_jq "pywal: high differs from critical" '.palette.high != .palette.critical' "true"
assert_jq "pywal: high differs from mid"      '.palette.high != .palette.mid'      "true"

# XDG_CACHE_HOME relocates the cache dir.
_wal_run "$WAL" "" custom --json
assert_jq "pywal: XDG_CACHE_HOME honored" '.palette.low' "#b8cc52"

# Omarchy theme outranks pywal.
_wal_run "$WAL" "$NAMED_THEME" home --json
assert_jq "pywal: Omarchy theme wins (low)"      '.palette.low'      "#9ece6a"
assert_jq "pywal: Omarchy theme wins (critical)" '.palette.critical' "#f7768e"

# Flags outrank everything.
_wal_run "$WAL" "" home --json --color-low '#123456'
assert_jq "pywal: --color-low outranks pywal"  '.palette.low'      "#123456"
assert_jq "pywal: other anchors still pywal"   '.palette.critical' "#ff3333"
_wal_run "$WAL" "$NAMED_THEME" home --json --color-critical '#abcdef'
assert_jq "pywal: flag outranks theme+pywal"   '.palette.critical' "#abcdef"

# Invalid/absent input degrades silently to One Dark — never an error.
_wal_run 'not json{{{' "" home --json
assert_exit0      "pywal garbage: exit 0"
assert_json_valid "pywal garbage: valid JSON"
assert_jq "pywal garbage: falls back to One Dark" '.palette.low'  "#98c379"
assert_jq "pywal garbage: no error field"         '.error'        "null"
_wal_run '{"special":{},"colors":{}}' "" home --json
assert_jq "pywal empty objects: One Dark"    '.palette.low' "#98c379"
_wal_run '{"colors":{"color2":"not-a-color","color1":"#ff3333"}}' "" home --json
assert_jq "pywal non-hex value ignored"      '.palette.low'      "#98c379"
assert_jq "pywal valid sibling still used"   '.palette.critical' "#ff3333"
# Short and alpha hex forms normalize to #rrggbb.
_wal_run '{"colors":{"color2":"#0f0","color1":"#ff3333ee"}}' "" home --json
assert_jq "pywal #rgb expanded"        '.palette.low'      "#00ff00"
assert_jq "pywal #rrggbbaa truncated"  '.palette.critical' "#ff3333"
assert_jq "pywal: palette still #RRGGBB" '[.palette | del(.stops) | .[] | test("^#[0-9a-fA-F]{6}$")] | all' "true"

# accent falls back to special.cursor when color4 is absent (tooltip title ink).
_wal_run '{"special":{"cursor":"#f29718"},"colors":{"color2":"#b8cc52"}}' "" home
if command grep -qF "foreground='#f29718'" <<<"$OUT"; then
    _ok "pywal: accent falls back to special.cursor"
else
    _no "pywal: accent falls back to special.cursor" "cursor color not used in tooltip"
fi

# --- Severity thresholds match the waybar classes ---
CRIT='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":92,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}}}'
run_codexbar "$CRIT" --json
assert_jq "json: 92% -> state critical"    '.state'            "critical"
assert_jq "json: 92% -> window critical"   '.windows[0].state' "critical"
assert_jq "json: 10% -> window low"        '.windows[1].state' "low"

# --- Additional model meters carry their group name ---
run_codexbar "$PROLITE" --json
assert_jq "json: additional windows appended"  '.windows | length' "4"
assert_jq "json: additional group name"        '.windows[2].group' "GPT-5.3-Codex-Spark"
assert_jq "json: additional window ids"        '[.windows[2,3].id] | join(",")' "additional_0_primary,additional_0_secondary"
assert_jq "json: main windows have null group" '.windows[0].group' "null"

# --- Single weekly window (secondary null): no mirrored duplicate ---
SINGLE='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":30,"reset_at":9999999999,"limit_window_seconds":604800},"secondary_window":null}}'
run_codexbar "$SINGLE" --json
assert_jq "json: single window not duplicated" '.windows | length' "1"
assert_jq "json: single window labeled Weekly" '.windows[0].label' "Weekly"

# --- Error path: still exit 0, valid JSON, error object set ---
run_codexbar_auth '{}' "$BASE" --json
assert_exit0      "json error: exit 0"
assert_json_valid "json error: valid JSON"
assert_jq "json error: object shape"     '.error | type'     "object"
assert_jq "json error: message present"  '.error.message | length > 0' "true"
assert_jq "json error: schema_version 2" '.schema_version'   "2"
assert_jq "json error: windows empty"    '.windows | length' "0"

# --- Arg errors answer in the structured shape when --json is anywhere ---
run_codexbar "$BASE" --json --icon
assert_exit0      "json arg error: exit 0"
assert_json_valid "json arg error: valid JSON"
assert_jq "json arg error: message"      '.error.message'  "--icon requires a value"
assert_jq "json arg error: schema"       '.schema_version' "2"
run_codexbar "$BASE" --badopt --json
assert_json_valid "json arg error: --json after bad flag still structured"
assert_jq "json arg error: unknown option message" '.error.message' "Unknown option: --badopt"
run_codexbar "$BASE" --icon x
assert_jq "waybar arg parse unaffected: class field present" '.class' "low"

# --- Control chars in messages survive as valid JSON (jq escaping) ---
run_codexbar "$BASE" --json "--bad$(printf '\t')opt"
assert_exit0      "json ctrl-char: exit 0"
assert_json_valid "json ctrl-char: valid JSON"
assert_jq "json ctrl-char: tab round-trips" '.error.message | test("bad\\topt")' "true"

# --- jq-less fallback: hand-escaped message, still valid JSON, exit 0 ---
# PATH holds only a curl stub: the dependency pre-check passes curl, then fails
# on jq. Without jq the message is escaped by hand rather than dropped, so the
# user still learns what actually failed.
_nojq_home=$(mktemp -d) || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
mkdir -p "$_nojq_home/bin"
printf '#!/bin/sh\nexit 1\n' > "$_nojq_home/bin/curl" && chmod +x "$_nojq_home/bin/curl"
_bash=$(command -v bash)
OUT=$(HOME="$_nojq_home" XDG_STATE_HOME="$_nojq_home/.local/state" XDG_CACHE_HOME="$_nojq_home/.cache" PATH="$_nojq_home/bin" "$_bash" "$(dirname "$0")/../codexbar" --json); RC=$?
assert_exit0      "json no-jq: exit 0"
assert_json_valid "json no-jq: valid JSON"
assert_jq "json no-jq: names the missing dependency" '.error.message | test("jq")' "true"
# Arg error without jq: fixed "invalid arguments" literal.
OUT=$(HOME="$_nojq_home" XDG_STATE_HOME="$_nojq_home/.local/state" XDG_CACHE_HOME="$_nojq_home/.cache" PATH="$_nojq_home/bin" "$_bash" "$(dirname "$0")/../codexbar" --json --icon); RC=$?
assert_exit0      "json no-jq arg error: exit 0"
assert_json_valid "json no-jq arg error: valid JSON"
assert_jq "json no-jq arg error: fixed literal" '.error.message' "invalid arguments"
rm -rf "$_nojq_home"

# --- --refresh bypasses the read cache; offline fallback stays structured ---
hdr=$(printf '{"alg":"RS256"}' | _b64url)
acc=$(printf '{"exp":4102444800}' | _b64url)
AUTH=$(jq -nc --arg at "$hdr.$acc.sig" '{tokens:{access_token:$at,refresh_token:"x",account_id:"a"}}')
run_codexbar_auth "$AUTH" "$BASE" --json --refresh
assert_exit0      "json --refresh: exit 0"
assert_json_valid "json --refresh: valid JSON"
assert_jq "json --refresh: cached data kept"     '.windows[0].used_pct' "46"
assert_jq "json --refresh: marked stale"         '.stale'        "true"
assert_jq "json --refresh: stale_reason network" '.stale_reason' "network"

finish
