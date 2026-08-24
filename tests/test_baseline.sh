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

BASE_REF="${BASE_REF:-0a0d5e3}"   # the tooltip meter reaches the right edge
REPO="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$(cat "$(dirname "$0")/fixtures/baseline.json")"

# Pango markup is stripped before comparing: the continuous color gradient
# (colors interpolate over used_pct; usage bars are per-cell ramps) is an
# intentional output change vs BASE_REF. Plain-text content, layout, padding,
# and glyph sequences stay guarded. Restore strict byte comparison by bumping
# BASE_REF once a release commit carries the gradient output.
norm() { sed 's/Updated [0-9][0-9]:[0-9][0-9]/Updated XX:XX/g; s/<[^>]*>//g'; }

# Working copies without git history (tarballs, sandbox copies) can't fetch
# the reference script — skip rather than fail on an unrunnable comparison.
if ! git -C "$REPO" cat-file -e "$BASE_REF:codexbar" 2>/dev/null; then
    printf '  skip baseline: %s not available (no git history here)\n' "$BASE_REF"
    finish
    exit $?
fi

base_script="$(mktemp)"
git -C "$REPO" show "$BASE_REF:codexbar" > "$base_script" && chmod +x "$base_script"

SCRIPT="$base_script" run_codexbar "$FIX" --tooltip-pace-pts; base_out="$(norm <<<"$OUT")"
run_codexbar "$FIX" --tooltip-pace-pts;                       new_out="$(norm <<<"$OUT")"
rm -f "$base_script"

if [[ "$base_out" == "$new_out" ]]; then
    _ok "no-flag output unchanged vs $BASE_REF (markup-normalized)"
else
    _no "no-flag output unchanged vs $BASE_REF (markup-normalized)" "$(diff <(printf '%s' "$base_out") <(printf '%s' "$new_out") | head -40)"
fi
finish
