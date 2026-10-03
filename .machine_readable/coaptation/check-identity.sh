#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# check-identity.sh — the IDENTITY gate for Coaptation. Deliberately nickel-free.
#
# verify.sh is the DRIFT gate: it asks "does the committed receipt still equal
# what the comparator would emit?", which requires re-evaluating coapt.ncl and
# therefore requires nickel. This gate asks a different and cheaper question:
#
#     does this pack declare THIS repository's identity, or has it reverted
#     to the template's?
#
# That needs no evaluator, so it runs anywhere — in CI, in a pre-commit hook, in
# a checkout with no toolchain at all. It is the executable form of issue #11's
# acceptance criterion ("no rsr-template-repo in coaptation/ except where it is
# an intentional drift-probe/fixture") and of the reason that issue existed at
# all: "so nothing silently reverts to the template identity".
#
# THREE CHECKS
#   1. IDENTITY LEAK — no file in coaptation/ carries the template's identity.
#      Without this, the re-pointing of #11 is a one-time edit with nothing
#      stopping a re-scaffold, a bad merge, or a copy-paste from upstream from
#      putting it straight back.
#   2. IDENTITY AGREEMENT — the committed receipt's `repo` is the repository's
#      declared canonical-name (CLADE.a2ml [identity]). This is the check the
#      old literal could not pass on principle: a literal agrees with the
#      descriptiles only by coincidence, and stops agreeing the moment either
#      side is edited.
#   3. NO HARDCODED IDENTITY — neither identity carrier (coapt.ncl, the Yard
#      comparator; coapt.sh, the Hunt writer) may contain a literal name. Both
#      must derive it. Two literals in two files is precisely how the template's
#      name survived instantiation (issue #8) and had to be re-pointed by hand
#      (issue #11).
#
# EXIT CODES
#   0 — identity is coherent          1 — a check failed          2 — setup error
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CO="$ROOT/.machine_readable/coaptation"
CLADE="$ROOT/.machine_readable/descriptiles/CLADE.a2ml"
RECEIPT="$CO/receipts/latest.a2ml"

# The template identity this repo was scaffolded from. Naming it here is the
# POINT of the script, so the script excludes itself from the scan below — the
# same reasoning scripts/check-no-placeholders.sh uses to allow-list itself.
TEMPLATE_IDENTITY='rsr-template-repo'

# Intentional carriers: files that must name the template identity, and are not
# identity CARRIERS themselves. Issue #11's acceptance criterion allows for
# these ("except where it is an intentional drift-probe/fixture"), and the list
# is here rather than implied so that an exemption is a decision someone made in
# a reviewed diff — not a pattern somebody widened.
#
#   README.adoc — documents this rule, and has to be able to quote the name it
#                 forbids. It is prose: no identity is read out of it, and no
#                 receipt field derives from it. Allow-listing a file that
#                 DECLARES an identity would defeat the gate; this one only
#                 describes it.
ALLOWED_FILES=(
    "$CO/README.adoc"
)
# A future drift-probe belongs here too:
# ALLOWED_FILES+=("$CO/fixtures/template-identity-probe.ncl")

for required in "$CO/coapt.ncl" "$CO/coapt.sh" "$CLADE"; do
    [ -f "$required" ] || { echo "check-identity: missing required file: $required" >&2; exit 2; }
done
[ -f "$RECEIPT" ] || { echo "check-identity: no coaptation receipt — run \`just coapt\`" >&2; exit 2; }

fails=0
fail() { printf 'FAIL: %s\n' "$1" >&2; printf '      %s\n' "$2" >&2; fails=$((fails + 1)); }

is_allowed() {
    local f="$1" a
    for a in "${ALLOWED_FILES[@]:-}"; do [ "$f" = "$a" ] && return 0; done
    return 1
}

# ── 1. the template's identity must not appear in the coaptation pack ─────────
#
# Comment-aware, and deliberately so: a comment explaining THAT the pattern is
# forbidden has to be able to name it. "Prose about a token is not a token" is
# the same distinction scripts/check-no-placeholders.sh draws with META_TOKENS.
#
# This is narrower than "comments are exempt" — it exempts a line whose first
# non-blank character is the comment sigil, not every line in a commented file.
leaks=""
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    path="${hit%%:*}"
    is_allowed "$path" && continue
    body="${hit#*:}"; body="${body#*:}"           # strip path:lineno:
    case "$body" in \#*) continue ;; esac         # a comment naming the leak is not the leak
    leaks="${leaks}${hit}"$'\n'
done < <(grep -rIn --exclude="$(basename "$0")" -- "$TEMPLATE_IDENTITY" "$CO" 2>/dev/null || true)

if [ -n "$leaks" ]; then
    fail "the template identity '$TEMPLATE_IDENTITY' is present in the coaptation pack" \
         "issue #11 re-pointed it; these lines carry it again (a real fixture belongs in ALLOWED_FILES):"
    printf '%s' "$leaks" | sed 's/^/        /' >&2
fi

# ── 2. the receipt must declare THIS repo's canonical name ────────────────────
canonical="$(grep -oP '^canonical-name = "\K[^"]+' "$CLADE" | head -1 || true)"
declared="$(grep -oP  '^repo = "\K[^"]+' "$RECEIPT" | head -1 || true)"

if [ -z "$canonical" ]; then
    fail "CLADE.a2ml declares no [identity] canonical-name" \
         "the coaptation receipt derives its repo identity from it; with no canonical-name the receipt cannot name this repo"
elif [ -z "$declared" ]; then
    fail "the coaptation receipt declares no repo" \
         "expected repo = \"$canonical\" in $RECEIPT"
elif [ "$canonical" != "$declared" ]; then
    fail "the receipt names a different repository than this one" \
         "CLADE.a2ml canonical-name = \"$canonical\", but the receipt says repo = \"$declared\""
fi

# ── 3. neither identity carrier may hardcode a name ───────────────────────────
#     `repo = "%{repo}"` and `repo = \"$REPO\"` are the derived forms: the value
#     begins with the interpolation sigil, so anything else there is a literal.
if grep -qE '^repo = "[^%]' "$CO/coapt.ncl"; then
    fail "coapt.ncl hardcodes the receipt's repo identity" \
         "derive it instead: let repo = (lookup \"clade.canonical-name\").value in ... repo = \"%{repo}\""
fi
if grep -qE 'repo = \\"[^$%]' "$CO/coapt.sh"; then
    fail "coapt.sh hardcodes a repo identity in the re-anchor basis" \
         "derive it from CLADE.a2ml canonical-name, as coapt.ncl does"
fi

if [ "$fails" -ne 0 ]; then
    echo "" >&2
    echo "The coaptation pack is a projection of this repository. A receipt that names" >&2
    echo "another repository is not a stale reading — it is a reading of nothing." >&2
    exit 1
fi

echo "OK: coaptation identity is coherent — repo = \"$declared\" (derived from CLADE.a2ml canonical-name)"
echo "    no '$TEMPLATE_IDENTITY' in the coaptation pack; neither carrier hardcodes a name"
