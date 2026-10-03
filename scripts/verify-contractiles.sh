#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Verify the six Hermeneia contractile tridents and their content manifests.
# This is a structural/integrity check: it does not evaluate Nickel, execute
# declared probes, validate owner approval, or replace the contractile CLI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:---check}"
case "$MODE" in
    --check) ;;
    --update-hashes) ;;
    *)
        echo "usage: bash scripts/verify-contractiles.sh [--check|--update-hashes]" >&2
        exit 64
        ;;
esac

VERBS=(intend must trust adjust dust bust)
XFILES=(Intentfile.a2ml Mustfile.a2ml Trustfile.a2ml Adjustfile.a2ml Dustfile.a2ml Bustfile.a2ml)
ERRORS=0

fail() {
    echo "FAIL: $*" >&2
    ERRORS=$((ERRORS + 1))
}

# Read the file entries in a manifest as tab-separated role/path/hash/size.
manifest_entries() {
    awk '
        /^\[\[files\]\]/ {
            if (inside) print role "\t" path "\t" hash "\t" size
            inside = 1
            role = path = hash = size = ""
            next
        }
        /^\[/ && inside {
            print role "\t" path "\t" hash "\t" size
            inside = 0
        }
        inside && /^role[[:space:]]*=/ {
            value = $0; sub(/^[^=]*=[[:space:]]*/, "", value); gsub(/\"/, "", value); role = value
        }
        inside && /^path[[:space:]]*=/ {
            value = $0; sub(/^[^=]*=[[:space:]]*/, "", value); gsub(/\"/, "", value); path = value
        }
        inside && /^sha256[[:space:]]*=/ {
            value = $0; sub(/^[^=]*=[[:space:]]*/, "", value); gsub(/\"/, "", value); sub(/[[:space:]#].*$/, "", value); hash = value
        }
        inside && /^size_bytes[[:space:]]*=/ {
            value = $0; sub(/^[^=]*=[[:space:]]*/, "", value); gsub(/\"/, "", value); sub(/[[:space:]#].*$/, "", value); size = value
        }
        END { if (inside) print role "\t" path "\t" hash "\t" size }
    ' "$1"
}

manifest_cross_ref() {
    awk -F= -v key="$2" '
        /^\[cross_refs\][[:space:]]*$/ { in_cross_refs = 1; next }
        /^\[/ && in_cross_refs { exit }
        in_cross_refs && $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
            value = $2
            gsub(/[[:space:]\"]/, "", value)
            print value
            exit
        }
    ' "$1"
}

rewrite_hashes() {
    local manifest="$1" h1="$2" s1="$3" h2="$4" s2="$5" h3="$6" s3="$7"
    local tmp
    tmp="$(mktemp "${manifest}.XXXXXX")"
    awk -v h1="$h1" -v s1="$s1" -v h2="$h2" -v s2="$s2" -v h3="$h3" -v s3="$s3" '
        /^\[\[files\]\]/ { block++ }
        /^sha256[[:space:]]*=/ && block >= 1 && block <= 3 {
            h = (block == 1 ? h1 : block == 2 ? h2 : h3)
            print "sha256 = \"" h "\""
            next
        }
        /^size_bytes[[:space:]]*=/ && block >= 1 && block <= 3 {
            s = (block == 1 ? s1 : block == 2 ? s2 : s3)
            print "size_bytes = \"" s "\""
            next
        }
        { print }
    ' "$manifest" > "$tmp"
    mv "$tmp" "$manifest"
}

for i in "${!VERBS[@]}"; do
    verb="${VERBS[$i]}"
    xfile="${XFILES[$i]}"
    dir=".machine_readable/contractiles/$verb"
    runner="$verb.ncl"
    k9="$verb.k9.ncl"
    manifest="$dir/$verb.manifest.a2ml"
    paths=("$xfile" "$runner" "$k9")
    roles=(declaration runner k9_component)

    for path in "${paths[@]}"; do
        if [[ ! -f "$dir/$path" ]]; then
            fail "$verb: missing $dir/$path"
        fi
    done
    if [[ ! -f "$manifest" ]]; then
        fail "$verb: missing $manifest"
        continue
    fi

    if ! grep -Fxq "verb = \"$verb\"" "$manifest"; then
        fail "$verb: manifest declares the wrong verb"
    fi
    [[ "$(manifest_cross_ref "$manifest" runner_paired_xfile)" == "$xfile" ]] || fail "$verb: manifest runner_paired_xfile is not reciprocal"
    [[ "$(manifest_cross_ref "$manifest" k9_paired_xfile)" == "../$verb/$xfile" ]] || fail "$verb: manifest k9_paired_xfile is not reciprocal"
    [[ "$(manifest_cross_ref "$manifest" k9_paired_runner)" == "../$verb/$runner" ]] || fail "$verb: manifest k9_paired_runner is not reciprocal"

    entries=()
    while IFS= read -r row; do
        [[ -n "$row" ]] && entries+=("$row")
    done < <(manifest_entries "$manifest")
    if [[ ${#entries[@]} -ne 3 ]]; then
        fail "$verb: expected exactly three manifest file entries, found ${#entries[@]}"
        continue
    fi

    hashes=()
    sizes=()
    for n in 0 1 2; do
        IFS=$'\t' read -r role path expected_hash expected_size <<< "${entries[$n]}"
        if [[ "$role" != "${roles[$n]}" ]]; then
            fail "$verb: file entry $((n + 1)) must have role ${roles[$n]}, got ${role:-<empty>}"
        fi
        if [[ "$path" != "${paths[$n]}" ]]; then
            fail "$verb: file entry $((n + 1)) must point to ${paths[$n]}, got ${path:-<empty>}"
            continue
        fi
        full_path="$dir/$path"
        if [[ ! -f "$full_path" ]]; then
            continue
        fi
        hashes[$n]="$(sha256sum "$full_path" | awk '{print $1}')"
        sizes[$n]="$(wc -c < "$full_path" | tr -d '[:space:]')"
        if [[ "$MODE" == "--check" ]]; then
            if [[ ! "$expected_hash" =~ ^[[:xdigit:]]{64}$ ]]; then
                fail "$verb: $path has no pinned SHA-256 in $manifest"
            elif [[ "$expected_hash" != "${hashes[$n]}" ]]; then
                fail "$verb: SHA-256 drift for $path (run bash scripts/verify-contractiles.sh --update-hashes after review)"
            fi
            if [[ ! "$expected_size" =~ ^[0-9]+$ ]]; then
                fail "$verb: $path has no numeric size_bytes in $manifest"
            elif [[ "$expected_size" != "${sizes[$n]}" ]]; then
                fail "$verb: size_bytes drift for $path (run bash scripts/verify-contractiles.sh --update-hashes after review)"
            fi
        fi
    done

    if [[ "$MODE" == "--update-hashes" && ${#hashes[@]} -eq 3 && ${#sizes[@]} -eq 3 ]]; then
        rewrite_hashes "$manifest" \
            "${hashes[0]}" "${sizes[0]}" \
            "${hashes[1]}" "${sizes[1]}" \
            "${hashes[2]}" "${sizes[2]}"
        echo "UPDATED: $manifest"
    fi

    # The runner and K9 component must point back to the declaration. These
    # are literal metadata links; semantic Nickel validation is intentionally
    # outside this script and remains subject to the separate K9-validator work.
    if [[ -f "$dir/$runner" ]] && ! grep -Fq "paired_xfile = \"$xfile\"" "$dir/$runner"; then
        fail "$verb: $runner does not name $xfile as its paired declaration"
    fi
    if [[ -f "$dir/$runner" ]]; then
        grep -Fq 'import "../_base.ncl"' "$dir/$runner" || fail "$verb: $runner does not import the project contractile base"
    fi
    if [[ -f "$dir/$k9" ]]; then
        grep -Fq "contractile_verb = \"$verb\"" "$dir/$k9" || fail "$verb: $k9 declares a different verb"
        grep -Fq "paired_xfile     = \"../$verb/$xfile\"" "$dir/$k9" || fail "$verb: $k9 paired_xfile is not reciprocal"
        grep -Fq "paired_runner    = \"../$verb/$runner\"" "$dir/$k9" || fail "$verb: $k9 paired_runner is not reciprocal"
        grep -Fq 'import "../_base.ncl"' "$dir/$k9" || fail "$verb: $k9 does not import the project contractile base"
        grep -Fq 'pedigree = base.pedigree_schema &' "$dir/$k9" || fail "$verb: $k9 does not use the project pedigree schema"
        grep -Fq "name = \"$verb.k9.ncl\"" "$dir/$k9" || fail "$verb: $k9 has no project-specific pedigree name"
        [[ -f "$dir/../_base.ncl" ]] || fail "$verb: shared contractile base is missing"
    fi
    grep -Fq "bash scripts/verify-contractiles.sh" .github/workflows/openssf-compliance.yml || fail "OpenSSF compliance workflow no longer runs the structural verifier"
    grep -Fq "verify-contractiles:" Justfile || fail "root Justfile no longer exposes verify-contractiles"
    grep -Fq "\"$verb/$xfile\"" .machine_readable/contractiles/INDEX.a2ml || fail "$verb: declaration is missing from INDEX.a2ml"
    grep -Fq "\"$verb/$runner\"" .machine_readable/contractiles/INDEX.a2ml || fail "$verb: runner is missing from INDEX.a2ml"
    grep -Fq "\"$verb/$k9\"" .machine_readable/contractiles/INDEX.a2ml || fail "$verb: K9 component is missing from INDEX.a2ml"
done

# These files are Hermeneia's live policy, not unfilled seed templates. The
# generic seed remains in machine-readable-design/ and is deliberately outside
# this project-specific directory.
if grep -RniE 'rsr-template-repo|REPLACE WITH PROJECT|canonical template in hermeneia|copy this trident into a new repo' .machine_readable/contractiles; then
    fail "generic template identity/content remains in .machine_readable/contractiles"
fi

if [[ "$ERRORS" -ne 0 ]]; then
    echo "Contractile trident verification failed with $ERRORS error(s)." >&2
    exit 1
fi

if [[ "$MODE" == "--update-hashes" ]]; then
    echo "Updated the six manifest hash/size sets. Re-run this script with --check."
else
    echo "OK: all six contractile tridents are structurally complete, cross-referenced, and hash-pinned."
    echo "NOTE: this does not run contractile probes, evaluate K9/Nickel, or imply owner ratification."
fi
