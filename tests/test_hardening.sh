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
finish
