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

finish
