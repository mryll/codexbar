#!/usr/bin/env bash
# Regression guard: default output identical to the last commit with an
# intentionally accepted output (bump BASE_REF when a release changes the output
# on purpose). A stored golden can't work (the tooltip embeds wall-clock time:
# "Updated HH:MM" + time-relative countdowns), so we run BOTH the base-commit
# script and the current script in the same instant and compare. Same `now` =>
# countdowns match; we normalize the "Updated HH:MM" minute for the rare case
# the two runs straddle a minute boundary (length-preserving, so box padding is
# unaffected).
source "$(dirname "$0")/lib.sh"

BASE_REF="${BASE_REF:-cc28df1}"   # v0.5.0 — plain tooltip default + --frame/--frame-font
REPO="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$(cat "$(dirname "$0")/fixtures/baseline.json")"

norm() { sed 's/Updated [0-9][0-9]:[0-9][0-9]/Updated XX:XX/g'; }

base_script="$(mktemp)"
git -C "$REPO" show "$BASE_REF:codexbar" > "$base_script" && chmod +x "$base_script"

SCRIPT="$base_script" run_codexbar "$FIX" --tooltip-pace-pts; base_out="$(norm <<<"$OUT")"
run_codexbar "$FIX" --tooltip-pace-pts;                       new_out="$(norm <<<"$OUT")"
rm -f "$base_script"

if [[ "$base_out" == "$new_out" ]]; then
    _ok "no-flag output unchanged vs $BASE_REF"
else
    _no "no-flag output unchanged vs $BASE_REF" "$(diff <(printf '%s' "$base_out") <(printf '%s' "$new_out") | head -40)"
fi
finish
