#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
# session 70% used, weekly 40%; reset_at far future -> elapsed ~0, remaining-time ~100
FIX='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":70,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":40,"reset_at":9999999999,"limit_window_seconds":604800}}}'

run_codexbar "$FIX" --remaining --tooltip-pace-pts
assert_exit0  "tooltip remaining: exit 0"
assert_tip_has "tooltip shows session remaining 30%" "30%"
assert_tip_has "tooltip shows weekly remaining 60%"  "60%"
assert_class  "class still severity (mid)" mid
assert_tip_has "remaining mode labels the header" "Codex Plus · Remaining"

# usage mode must NOT add the Remaining label
run_codexbar "$FIX" --tooltip-pace-pts
assert_tip_lacks "usage mode header has no Remaining label" "Remaining"

# New API shape: a single weekly limit lives in primary_window
# (limit_window_seconds ≈ 7d) and secondary_window is null. The primary row
# must be labeled by its real duration and the empty secondary row must
# disappear (no misleading "Weekly 0%").
FIX_SINGLE='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":7,"reset_at":9999999999,"limit_window_seconds":604800},"secondary_window":null},"code_review_rate_limit":null,"additional_rate_limits":null}'
run_codexbar "$FIX_SINGLE"
assert_exit0     "single weekly window: exit 0"
assert_tip_has   "single weekly window: primary labeled Weekly" "Weekly"
assert_tip_lacks "single weekly window: no Session row" "Session"
assert_tip_lacks "single weekly window: no empty 0% row" "0%"
assert_class     "single weekly window: severity from the one window" low

# {weekly_*} placeholders mirror the single weekly window instead of reading 0
run_codexbar "$FIX_SINGLE" --format '{weekly_pct}%W {session_pct}%S'
assert_text_has "single weekly window: {weekly_pct} mirrors primary" "7%W"
assert_text_has "single weekly window: {session_pct} still primary" "7%S"
finish
