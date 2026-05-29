#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
FIX='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":46,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":47,"reset_at":9999999999,"limit_window_seconds":604800}}}'

run_codexbar "$FIX" --remaining
assert_exit0    "remaining: exit 0"
assert_text_has "remaining: bar text shows 54% (100-46)" "54%"

run_codexbar "$FIX" --remaining --format '{session_pct}% used'
assert_text_has "remaining + custom --format: user format wins (46% used)" "46% used"
finish
