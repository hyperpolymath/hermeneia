#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# verify.sh — the Yard-tier drift gate for the coaptation receipt (the runnable
# side of coapt.k9.ncl). Regenerates the receipt from the contractiles +
# descriptiles and byte-compares it to the committed receipts/latest.a2ml.
# Non-zero exit on drift or hand-edit. Wire into CI/pre-commit.
#
# The receipt is a drift-checked PROJECTION: if the normative set-point or the
# descriptive self-model changed without re-running `just coapt`, this fails —
# the reading on record no longer matches reality.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
CO="$ROOT/.machine_readable/coaptation"
TARGET="$CO/receipts/latest.a2ml"

[ -f "$TARGET" ] || { echo "DRIFT: coaptation receipt missing — run \`just coapt\`"; exit 1; }

command -v nickel >/dev/null 2>&1 || {
  echo "verify.sh: 'nickel' is required to re-evaluate the comparator and is not on PATH." >&2
  echo "           Install it (see .machine_readable/self-validating/README.adoc) or run this" >&2
  echo "           inside the dev container, which provisions it." >&2
  echo "           The nickel-free identity gate is .machine_readable/coaptation/check-identity.sh." >&2
  exit 2
}

bash "$CO/extract-clauses.sh" "$ROOT/.machine_readable/contractiles" > "$CO/clauses.json"
bash "$CO/extract-facts.sh"   "$ROOT/.machine_readable/descriptiles"           > "$CO/facts.json"

fresh="$(nickel export --format raw "$CO/coapt.ncl")"
committed="$(cat "$TARGET")"

# A receipt that read ZERO clauses is not a reading — it is the atomiser having
# failed quietly, and a drift gate that accepts it has laundered the failure
# into a baseline. See the PORTABILITY note in extract-clauses.sh: an awk that
# does not support the {n,m} interval expression (mawk, the default on Debian
# and Ubuntu) does not error on the pattern, it simply never matches it, and the
# runner still exits 0. The symptom was a well-formed receipt reporting
# `clauses-total = 0`, which then compared equal to nothing.
total="$(printf '%s\n' "$fresh" | grep -oP '^clauses-total = \K[0-9]+' | head -1 || true)"
if [ "${total:-0}" -eq 0 ]; then
  echo "DRIFT: the regenerated receipt read 0 contractile clauses." >&2
  echo "       A coaptation of an empty clause set is not a reading of anything." >&2
  echo "       Check extract-clauses.sh against the awk on this machine" >&2
  echo "       (\`awk --version\`; mawk does not support {n,m} intervals)." >&2
  exit 1
fi

if [ "$fresh" = "$committed" ]; then
  echo "OK: coaptation receipt is in sync with the contractiles + descriptiles."
else
  echo "DRIFT: coaptation receipt is stale (contractiles/descriptiles changed, or receipt hand-edited)."
  echo "       Run \`just coapt\` to regenerate. Diff (committed → fresh):"
  diff <(printf '%s\n' "$committed") <(printf '%s\n' "$fresh") || true
  exit 1
fi
