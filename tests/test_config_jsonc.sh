#!/usr/bin/env bash
# =============================================================================
# Hoplon config tests.
#
# Strips JSONC comments, validates both configs parse as strict JSON with jq,
# then asserts the model contract that ties config/opencode.jsonc and
# config/omo.jsonc together:
#   * the Venice whitelist has exactly 7 entries
#   * the oracle agent is venice/qwen-3-6-plus in both files
#   * the plugin array carries exactly one pinned oh-my-openagent entry
#
# Usage: tests/test_config_jsonc.sh
# Requires: bash, awk, jq, grep
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd -P)"
OPENCODE_CFG="$ROOT/config/opencode.jsonc"
OMO_CFG="$ROOT/config/omo.jsonc"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}
pass() { printf 'ok: %s\n' "$*"; }

# Sanitise JSONC into strict JSON: drop // and /* */ comments and trailing
# commas, all while leaving string contents untouched (so a URL such as
# "https://api.venice.ai/api/v1" survives). opencode's parser accepts JSONC, but
# jq does not, so this normalisation is what lets jq be the validator.
strip_jsonc() {
  awk '
    { text = text $0 "\n" }
    END {
      n = length(text); out = ""; instr = 0; esc = 0; inblock = 0; pending = 0; i = 1
      while (i <= n) {
        c = substr(text, i, 1); two = substr(text, i, 2)
        if (inblock) {
          if (two == "*/") { inblock = 0; i += 2 } else { i++ }
          continue
        }
        if (instr) {
          if (pending) { out = out ","; pending = 0 }
          out = out c
          if (esc) { esc = 0 }
          else if (c == "\\") { esc = 1 }
          else if (c == "\"") { instr = 0 }
          i++; continue
        }
        if (c == "\"") {
          if (pending) { out = out ","; pending = 0 }
          instr = 1; out = out c; i++; continue
        }
        if (two == "//") {
          j = index(substr(text, i), "\n")
          if (j == 0) { i = n + 1 } else { i = i + j - 1 }
          continue
        }
        if (two == "/*") { inblock = 1; i += 2; continue }
        if (c == ",") { pending = 1; i++; continue }
        if (c == "}" || c == "]") { pending = 0; out = out c; i++; continue }
        if (pending && c !~ /[ \t\r\n]/) { out = out ","; pending = 0 }
        out = out c; i++
      }
      printf "%s", out
    }
  ' "$1"
}

[ -f "$OPENCODE_CFG" ] || fail "missing $OPENCODE_CFG"
[ -f "$OMO_CFG" ] || fail "missing $OMO_CFG"

# --- JSONC parses as strict JSON after comment stripping ---------------------
oc_json="$(strip_jsonc "$OPENCODE_CFG")"
omo_json="$(strip_jsonc "$OMO_CFG")"
printf '%s' "$oc_json" | jq -e . > /dev/null ||
  fail "config/opencode.jsonc does not parse as JSON after comment stripping"
printf '%s' "$omo_json" | jq -e . > /dev/null ||
  fail "config/omo.jsonc does not parse as JSON after comment stripping"
pass "both JSONC configs parse"

# --- Venice whitelist: exactly 7 entries -------------------------------------
wl_len="$(printf '%s' "$oc_json" | jq -r '.provider.venice.whitelist | length')"
[ "$wl_len" = "7" ] || fail "venice whitelist must have 7 entries, found $wl_len"
pass "venice whitelist has exactly 7 entries"

# --- oracle model is venice/qwen-3-6-plus in both files ----------------------
oc_oracle="$(printf '%s' "$oc_json" | jq -r '.agent.oracle.model')"
omo_oracle="$(printf '%s' "$omo_json" | jq -r '.["[opencode]"].agents.oracle.model')"
[ "$oc_oracle" = "venice/qwen-3-6-plus" ] ||
  fail "config/opencode.jsonc oracle model is '$oc_oracle', expected venice/qwen-3-6-plus"
[ "$omo_oracle" = "venice/qwen-3-6-plus" ] ||
  fail "config/omo.jsonc oracle model is '$omo_oracle', expected venice/qwen-3-6-plus"
pass "oracle is venice/qwen-3-6-plus in both configs"

# --- plugin grep contract ----------------------------------------------------
omo_lines="$(grep -c '"oh-my-openagent@' "$OPENCODE_CFG" || true)"
[ "$omo_lines" = "1" ] ||
  fail "expected exactly one pinned oh-my-openagent plugin entry, found $omo_lines"
grep -q '"oh-my-openagent@5.0.0-beta.62"' "$OPENCODE_CFG" ||
  fail "oh-my-openagent plugin pin is not 5.0.0-beta.62"
grep -q '"@cortexkit/opencode-magic-context@0.42.2"' "$OPENCODE_CFG" ||
  fail "magic-context plugin entry is missing"
plugin_count="$(printf '%s' "$oc_json" | jq -r '.plugin | length')"
[ "$plugin_count" = "2" ] ||
  fail "plugin array must hold exactly 2 entries, found $plugin_count"
pass "plugin grep contract holds (one OMO pin, one Magic Context)"

printf 'PASS: config/opencode.jsonc and config/omo.jsonc\n'
