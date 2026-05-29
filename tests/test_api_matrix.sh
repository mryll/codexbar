#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
R(){ run_codexbar "$1" "${@:2}"; assert_exit0 "$LBL"; assert_json_valid "$LBL"; }

# minimal Plus
LBL="minimal plus"; R '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":46,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":47,"reset_at":9999999999,"limit_window_seconds":604800}}}'
# code review present
LBL="review present"; R '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":1,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":1,"reset_at":9999999999,"limit_window_seconds":604800}},"code_review_rate_limit":{"primary_window":{"used_percent":4,"reset_at":9999999999,"limit_window_seconds":604800}}}'
# credits unlimited + ranges
LBL="credits"; R '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":1,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":1,"reset_at":9999999999,"limit_window_seconds":604800}},"credits":{"has_credits":true,"unlimited":true,"balance":"5","approx_local_messages":[1,9],"approx_cloud_messages":[2,2]}}'
# additional: null / [] / scalar / empty-name / window 0 / one-window / >100
for ADD in 'null' '[]' '[1,"x"]' '[{"limit_name":"","metered_feature":"codex_x","rate_limit":{"primary_window":{"used_percent":5,"limit_window_seconds":18000}}}]' '[{"limit_name":"Z","rate_limit":{"primary_window":{"used_percent":99,"limit_window_seconds":0}}}]' '[{"limit_name":"One","rate_limit":{"secondary_window":{"used_percent":5,"limit_window_seconds":604800}}}]' '[{"limit_name":"Over","rate_limit":{"primary_window":{"used_percent":150,"limit_window_seconds":18000}}}]'; do
  LBL="additional=$ADD (usage)";     R "{\"plan_type\":\"plus\",\"rate_limit\":{\"primary_window\":{\"used_percent\":5,\"reset_at\":9999999999,\"limit_window_seconds\":18000},\"secondary_window\":{\"used_percent\":5,\"reset_at\":9999999999,\"limit_window_seconds\":604800}},\"additional_rate_limits\":$ADD}"
  LBL="additional=$ADD (remaining)"; R "{\"plan_type\":\"plus\",\"rate_limit\":{\"primary_window\":{\"used_percent\":5,\"reset_at\":9999999999,\"limit_window_seconds\":18000},\"secondary_window\":{\"used_percent\":5,\"reset_at\":9999999999,\"limit_window_seconds\":604800}},\"additional_rate_limits\":$ADD}" --remaining --tooltip-pace-pts
done
# field abuse: string pct, missing reset, fractional window, non-object containers
LBL="string pct"; R '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":"x","reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}}}'
LBL="missing reset (now)"; R '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"limit_window_seconds":604800}}}'
LBL="fractional window"; R '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":0.5},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}}}'
LBL="non-object window"; R '{"plan_type":"plus","rate_limit":{"primary_window":1,"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}}}'
LBL="non-object rate_limit"; R '{"plan_type":"plus","rate_limit":7}'
LBL="non-object credits"; R '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}},"credits":9}'
# plan_type variants (incl. non-string)
for P in '"plus"' '"prolite"' '"self_serve_business_usage_based"' '"enterprise_cbp_usage_based"' '"unknown"' 'null' '["a"]'; do
  LBL="plan=$P"; R "{\"plan_type\":$P,\"rate_limit\":{\"primary_window\":{\"used_percent\":10,\"reset_at\":9999999999,\"limit_window_seconds\":18000},\"secondary_window\":{\"used_percent\":10,\"reset_at\":9999999999,\"limit_window_seconds\":604800}}}"
done
# Pro Lite label
run_codexbar '{"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}}}'
assert_tip_has "prolite -> Pro Lite" "Codex Pro Lite"
# flag-combination invariants on a normal payload
NORM='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":46,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":47,"reset_at":9999999999,"limit_window_seconds":604800}}}'
run_codexbar "$NORM" --remaining --format '{session_pct}% used'
assert_text_has "remaining + user --format wins" "46% used"
run_codexbar "$NORM" --remaining
assert_text_has "remaining default bar shows remaining" "54%"
finish
