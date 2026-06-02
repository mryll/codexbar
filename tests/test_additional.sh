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

# REGRESSION: blank limit_name must still render (fall back to metered_feature)
# and stay in sync with severity — a windowed 95% meter must NOT become a hidden
# meter that colors the widget critical without showing in the tooltip.
FIX3='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":604800}},"additional_rate_limits":[{"limit_name":"","metered_feature":"codex_x","rate_limit":{"primary_window":{"used_percent":95,"reset_at":9999999999,"limit_window_seconds":18000}}}]}'
run_codexbar "$FIX3" --remaining --tooltip-pace-pts
assert_exit0   "blank limit_name: exit 0"
assert_tip_has "blank limit_name falls back to metered_feature" "codex_x"
assert_class   "blank limit_name 95% counts toward severity" critical

# --- Option A layout: two-window additional meter (observed Spark shape) ---
SPARK="$(cat "$(dirname "$0")/fixtures/usage-prolite-spark.json")"
run_codexbar "$SPARK" --tooltip-pace-pts
assert_exit0      "spark two-window: exit 0"
assert_json_valid "spark two-window: valid JSON"
assert_tip_has    "spark model name shown" "GPT-5.3-Codex-Spark"
# icon attached to the right window — stronger than bare '5h'/'Weekly'
# ('Weekly' alone also matches the top-level block); also asserts ${label^}
assert_tip_has    "primary window header has 5h icon"     "󰔟  5h"
assert_tip_has    "secondary window header has Weekly icon" "󰃰  Weekly"
# label moved out of the reset line into the header (new layout vs old)
assert_tip_lacks  "old primary reset prefix gone"   "5h resets in"
assert_tip_lacks  "old secondary reset prefix gone" "Weekly resets in"
assert_tip_has    "reset line still present" "Resets in"
# block emits in order: model -> 5h header -> bar -> reset -> Weekly header -> bar -> reset
if _plain .tooltip | awk '
  /GPT-5.3-Codex-Spark/ { s=1 }
  s && /󰔟  5h/     && st==0 { st=1; next }
  s && /%/          && st==1 { st=2; next }
  s && /Resets in/  && st==2 { st=3; next }
  s && /󰃰  Weekly/ && st==3 { st=4; next }
  s && /%/          && st==4 { st=5; next }
  s && /Resets in/  && st==5 { st=6; next }
  END { exit (st==6 ? 0 : 1) }'; then
  _ok "additional block renders in expected order"
else
  _no "additional block renders in expected order" "order/structure mismatch"
fi

# --- Pango-escape of limit_name (regression) ---
ESC='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":604800}},"additional_rate_limits":[{"limit_name":"A<B&C>","rate_limit":{"primary_window":{"used_percent":5,"reset_at":9999999999,"limit_window_seconds":18000}}}]}'
run_codexbar "$ESC" --tooltip-pace-pts
assert_exit0      "pango-escape: exit 0"
assert_json_valid "pango-escape: valid JSON"
assert_tip_has    "limit_name angle/amp escaped" "A&lt;B&amp;C&gt;"
finish
