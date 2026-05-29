#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
FIX='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":46,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":47,"reset_at":9999999999,"limit_window_seconds":604800}}}'

run_codexbar "$FIX" --format '{session_remaining_bar}'
assert_exit0   "remaining_bar placeholder: exit 0"
_plain .text | grep -qF '{session_remaining_bar}' && _no "placeholder resolved" "left literal" || _ok "placeholder resolved"
assert_text_has "remaining_bar renders blocks" "█"
finish
