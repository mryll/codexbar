#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
# session 70% used, weekly 40%; reset_at far future -> elapsed ~0, remaining-time ~100
FIX='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":70,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":40,"reset_at":9999999999,"limit_window_seconds":604800}}}'

run_codexbar "$FIX" --remaining --tooltip-pace-pts
assert_exit0  "tooltip remaining: exit 0"
assert_tip_has "tooltip shows session remaining 30%" "30%"
assert_tip_has "tooltip shows weekly remaining 60%"  "60%"
assert_class  "class still severity (mid)" mid
finish
