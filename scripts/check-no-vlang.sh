#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# check-no-vlang.sh — enforce "V-lang is banned in the estate".
#
# Estate rule: V (vlang.io) is banned. The connector layer it used to provide
# is replaced by `zig-unified-api-adapter` (16 endpoints + transaction-firewall
# gating). Treat any V reference as drift and remove it.
#
# NOTE: this checks for *V-lang*, not Zig. Zig is an ALLOWED estate language
# (the default for APIs/FFIs/gateways per hyperpolymath/standards). Do not add
# `zig` to the pattern list — `build.zig`, `zig build`, and FFI-in-Zig are all
# legitimate.
#
# Searches for V-specific patterns in tracked files. The .v file extension is
# intentionally NOT used as a marker because Coq theorem files (and Verilog)
# share that extension; this check looks at content/naming patterns instead.
#
# Excludes:
#   .git/ (vcs internals)
#   affinescript/ (a separately-licensed AffineScript subtree; pattern hits
#       there are not estate-managed and false-positive on `.v` mentions in
#       linguistic / academic prose).
#
# Exit codes:
#   0 — no V references found
#   1 — V references found (treat as drift)
#   2 — usage / setup error

set -euo pipefail

REPO_ROOT="${1:-.}"

# Patterns that uniquely indicate V (vlang) code, scaffolding, or naming.
# Coq's `.v` extension and the affinescript subtree are excluded by path.
# Do NOT add `zig` here: Zig is an allowed estate language.
PATTERNS=(
    'gen-v-connector'
    'V-TRIPLE'
    'v-triple'
    'vlang'
    'v\.mod'
    'connectors/v-'
)

PATTERN_OR=$(IFS='|'; echo "${PATTERNS[*]}")

# Files that document the V ban itself (the rule's own description
# legitimately names "vlang", "V-TRIPLE", etc.). Excluded by name.
DOC_EXCLUSIONS=(
    "estate-rules.yml"             # the workflow that calls this script
    "check-no-vlang.sh"            # this script itself
    "PLAYBOOK.a2ml"                # documents the [rsr-repo-skeleton] rules
    "feedback_v_lang_banned.md"    # memory entry documenting the ban
    "project_zig_unified_api.md"   # memory entry documenting the replacement
)

EXCLUDE_ARGS=()
for f in "${DOC_EXCLUSIONS[@]}"; do
    EXCLUDE_ARGS+=(--exclude="$f")
done

# Build grep arguments. Use -r to recurse, -n for line numbers, -i for
# case-insensitive matching. Exclude .git, the affinescript subtree, and
# files that legitimately document the ban.
HITS=$(grep -rni -E "$PATTERN_OR" "$REPO_ROOT" \
    --exclude-dir=.git \
    --exclude-dir=affinescript \
    --exclude-dir=node_modules \
    "${EXCLUDE_ARGS[@]}" \
    2>/dev/null || true)

if [ -z "$HITS" ]; then
    echo "PASS: no V references"
    exit 0
fi

# Count matches
LINES=$(echo "$HITS" | wc -l | tr -d ' ')

echo "FAIL: $LINES V reference(s) found (estate rule: V-lang is banned):" >&2
echo "$HITS" | sed 's|^|  |' >&2
echo "" >&2
echo "V has been replaced by zig-unified-api-adapter. Remove these references." >&2
exit 1
