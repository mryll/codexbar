#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
# Spark primary 80% used (window valid) -> remaining 20%
FIX='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}},"additional_rate_limits":[{"limit_name":"Spark","rate_limit":{"primary_window":{"used_percent":80,"reset_at":9999999999,"limit_window_seconds":18000}}}]}'
run_codexbar "$FIX" --remaining --tooltip-pace-pts
assert_exit0   "additional remaining: exit 0"
assert_tip_has "additional meter name shown" "Spark"
assert_tip_has "Spark remaining 20% shown" "20%"

# used_percent > 100 must clamp (remaining 0), no crash / no broken bar
FIX2='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}},"additional_rate_limits":[{"limit_name":"Over","rate_limit":{"primary_window":{"used_percent":130,"reset_at":9999999999,"limit_window_seconds":18000}}}]}'
run_codexbar "$FIX2" --remaining
assert_exit0      "additional >100% clamp: exit 0"
assert_json_valid "additional >100% clamp: valid JSON"
finish
