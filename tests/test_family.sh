#!/usr/bin/env bash
# Family contract: the rules codexbar and claudebar must answer the same way.
# Every assertion here has a byte-identical twin in claudebar/tests/test_family.sh
# (only the script name and the fixture change). When the two files stop
# mirroring each other, the family has drifted.
source "$(dirname "$0")/lib.sh"
MIN='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":34,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":58,"reset_at":9999999999,"limit_window_seconds":604800}}}'

echo "== --help prints the reference and exits 0"
HELP=$("$SCRIPT" --help); RC=$?
[[ "$RC" -eq 0 ]] && _ok "--help: exit 0" || _no "--help: exit 0" "exit=$RC"
grep -q '^Usage: ' <<<"$HELP"            && _ok "--help: usage line"   || _no "--help: usage line" "$HELP"
grep -q -- '--no-color' <<<"$HELP"       && _ok "--help: documents --no-color" || _no "--help: documents --no-color" "missing"
grep -q -- '--frame' <<<"$HELP"          && _ok "--help: documents --frame"    || _no "--help: documents --frame" "missing"
grep -q '{icon}' <<<"$HELP"              && _ok "--help: documents {icon}"     || _no "--help: documents {icon}" "missing"
grep -q '^#' <<<"$HELP"                  && _no "--help: comment marks stripped" "leaked #" || _ok "--help: comment marks stripped"
HELP_H=$("$SCRIPT" -h)
[[ "$HELP_H" == "$HELP" ]] && _ok "-h is the same as --help" || _no "-h is the same as --help" "differs"

echo "== {icon} resolves to the widget mark"
run_codexbar "$MIN" --format '{icon}'
assert_exit0 "{icon}: exit 0"
_plain .text | grep -qF '{icon}' && _no "{icon} resolved" "left literal" || _ok "{icon} resolved"
_plain .text | grep -q '[^[:space:]]' && _ok "{icon} is not empty" || _no "{icon} is not empty" "blank"

echo "== --no-color strips UNQUOTED color attributes too"
run_codexbar "$MIN" --no-color --format "<span foreground=red>X</span> {session_pct}%"
assert_exit0 "unquoted attr: exit 0"
jq -r .text <<<"$OUT" | grep -q 'foreground' \
    && _no "unquoted foreground= stripped" "$(jq -r .text <<<"$OUT")" \
    || _ok "unquoted foreground= stripped"
jq -r .text <<<"$OUT" | grep -qF 'X' && _ok "…while the text survives" || _no "…while the text survives" "lost"

echo "== the bar tint is the continuous ramp at the DISPLAYED value"
# 34% sits between the low and mid anchors, so a stepped scale would paint it
# exactly the low anchor. The ramp must not.
run_codexbar "$MIN" --color-low '#000000' --color-mid '#ffffff' --format '{session_pct}%'
assert_exit0 "ramp: exit 0"
TINT=$(jq -r .text <<<"$OUT" | sed -n "s/.*foreground='\([^']*\)'.*/\1/p" | head -1)
[[ "$TINT" != "#000000" && "$TINT" != "" ]] \
    && _ok "34% is interpolated, not the low anchor ($TINT)" \
    || _no "34% is interpolated, not the low anchor" "tint=$TINT"

echo "== the network-loading tooltip breaks the line for real"
_lh=$(mktemp -d) || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
mkdir -p "$_lh/bin" "$_lh/.codex"
printf '#!/usr/bin/env bash\nexit 1\n' > "$_lh/bin/curl" && chmod +x "$_lh/bin/curl"
_hdr=$(printf '{"alg":"RS256"}' | _b64url)
_acc=$(printf '{"exp":4102444800}' | _b64url)
_idt=$(printf '{"https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}' | _b64url)
jq -nc --arg at "$_hdr.$_acc.sig" --arg idt "$_hdr.$_idt.sig" \
    '{tokens:{access_token:$at,refresh_token:"x",account_id:"a",id_token:$idt}}' > "$_lh/.codex/auth.json"
OUT=$(HOME="$_lh" XDG_STATE_HOME="$_lh/.local/state" XDG_CACHE_HOME="$_lh/.cache" \
      XDG_CONFIG_HOME="$_lh/.config" PATH="$_lh/bin:$PATH" "$SCRIPT"); RC=$?
rm -rf "$_lh"
assert_exit0 "loading: exit 0"
jq -r .tooltip <<<"$OUT" | grep -qF '\n' \
    && _no "loading tooltip has no literal backslash-n" "$(jq -r .tooltip <<<"$OUT")" \
    || _ok "loading tooltip has no literal backslash-n"
[[ $(jq -r .tooltip <<<"$OUT" | wc -l) -ge 2 ]] \
    && _ok "loading tooltip is two real lines" \
    || _no "loading tooltip is two real lines" "$(jq -r .tooltip <<<"$OUT")"

echo "== the tooltip does not depend on the caller's locale"
# ${#var} counts BYTES under a C locale, so every multibyte glyph — the bar
# cells █░, the Nerd Font icons — used to inflate a line's measured width and
# the rules were drawn ~20 characters longer than the text they underline.
# Waybar started from a systemd unit with no locale is exactly this case.
_widest() { jq -r .tooltip <<<"$1" | sed 's/<[^>]*>//g' | awk '{print length($0)}' | sort -rn | head -1; }
LC_ALL=en_US.UTF-8 run_codexbar "$MIN"; _utf8=$(_widest "$OUT")
LC_ALL=C           run_codexbar "$MIN"; _c=$(_widest "$OUT")
[[ "$_utf8" == "$_c" && -n "$_utf8" ]] \
    && _ok "the rules are the same width under C and UTF-8 ($_utf8)" \
    || _no "the rules are the same width under C and UTF-8" "utf8=$_utf8 C=$_c"

finish
