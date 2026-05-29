#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
FIX='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":46,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":47,"reset_at":9999999999,"limit_window_seconds":604800}}}'
run_codexbar "$FIX"
assert_exit0      "smoke: exit 0"
assert_json_valid "smoke: valid JSON"
assert_class      "smoke: class low" low
assert_text_has   "smoke: shows 46%" "46%"
finish
