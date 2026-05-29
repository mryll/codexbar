#!/usr/bin/env bash
# Malformed local credentials must never crash the widget (it must still exit 0
# with valid JSON). Pre-existing gap: jwt_decode could emit non-JSON, and the
# jq parsing it (jwt_exp / plan extraction) would parse-error under set -e.
source "$(dirname "$0")/lib.sh"
b64(){ base64 -w0 | tr '+/' '-_' | tr -d '='; }
HDR=$(printf '{"alg":"RS256"}' | b64)
USAGE='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":18000},"secondary_window":{"used_percent":10,"reset_at":9999999999,"limit_window_seconds":604800}}}'
mkauth(){ jq -nc --arg at "$1" --arg idt "$2" '{tokens:{access_token:$at,refresh_token:"x",account_id:"a",id_token:$idt}}'; }

NONJSON="$HDR.$(printf 'hello world' | b64).sig"               # base64 decodes to non-JSON
EXPSTR="$HDR.$(printf '{"exp":"not-a-number"}' | b64).sig"     # valid JSON, exp wrong type
GOODACC="$HDR.$(printf '{"exp":4102444800}' | b64).sig"        # valid far-future (no refresh)
BADCLAIM="$HDR.$(printf '{"https://api.openai.com/auth":"oops"}' | b64).sig"  # auth claim non-object
GARBAGE="totally-not-a-jwt"                                     # no dots / not base64

run_codexbar_auth "$(mkauth "$NONJSON" "$NONJSON")" "$USAGE"
assert_exit0 "non-JSON access+id token: exit 0"; assert_json_valid "non-JSON tokens: valid JSON"

run_codexbar_auth "$(mkauth "$EXPSTR" "$GOODACC")" "$USAGE"
assert_exit0 "exp as string: exit 0"; assert_json_valid "exp as string: valid JSON"

run_codexbar_auth "$(mkauth "$GOODACC" "$BADCLAIM")" "$USAGE"
assert_exit0 "non-object auth claim: exit 0"; assert_json_valid "non-object auth claim: valid JSON"

run_codexbar_auth "$(mkauth "$GARBAGE" "$GARBAGE")" "$USAGE"
assert_exit0 "garbage tokens: exit 0"; assert_json_valid "garbage tokens: valid JSON"

# valid JSON but non-object ROOT type (scalar / array / number) must not crash
SCALAR="$HDR.$(printf '"just-a-string"' | b64).sig"
ARRAY="$HDR.$(printf '[1,2,3]' | b64).sig"
NUMBER="$HDR.$(printf '42' | b64).sig"
run_codexbar_auth "$(mkauth "$SCALAR" "$ARRAY")" "$USAGE"
assert_exit0 "scalar/array root JWT: exit 0"; assert_json_valid "scalar/array root: valid JSON"
run_codexbar_auth "$(mkauth "$NUMBER" "$GOODACC")" "$USAGE"
assert_exit0 "number root JWT (exp path): exit 0"; assert_json_valid "number root: valid JSON"
finish
