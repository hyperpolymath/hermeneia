#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# instantiate.sh — render this repository's {{PLACEHOLDER}} tokens from
#                  .machine_readable/configs/instantiation.a2ml.
#
# hermeneia was scaffolded from hyperpolymath/rsr-template-repo and the
# template's own bootstrap was never run, so ~120 files shipped as an
# unrendered template (issue #8). Filling them by hand once fixes the symptom
# and loses the decisions: nothing can re-run it, check it, or notice when a
# re-sync from the template brings a token back. This script keeps the
# decisions in a committed manifest instead.
#
# It is the local equivalent of the estate's `build/just/repo-init.just` mint,
# narrowed to what a repo that ALREADY EXISTS needs — no archetype overlays, no
# docs-seed, no deed splicing, no provenance rewrite. Those happen once, at
# mint, in the template. This happens whenever a token comes back.
#
# Idempotent by construction: substitution is token -> value, a rendered tree
# holds no tokens, so a second pass changes nothing.
#
# Usage:
#   scripts/instantiate.sh              render, then verify with the estate gate
#   scripts/instantiate.sh --render     render only
#   scripts/instantiate.sh --check      verify only; exit 1 if anything would change
#   scripts/instantiate.sh --list       print the resolved token table and exit
#
# Exit codes:
#   0 — rendered (or already rendered) and clean
#   1 — a token is left unfilled, or --check found drift
#   2 — usage / setup error

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MANIFEST=".machine_readable/configs/instantiation.a2ml"
GATE="scripts/check-no-placeholders.sh"

MODE="render+verify"
case "${1:-}" in
    --render) MODE="render" ;;
    --check)  MODE="check" ;;
    --list)   MODE="list" ;;
    "")       ;;
    *) echo "usage: $0 [--render|--check|--list]" >&2; exit 2 ;;
esac

command -v awk >/dev/null 2>&1 || { echo "ERROR: awk is required" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "ERROR: $MANIFEST not found" >&2; exit 2; }

# ─── Read the [tokens] manifest ──────────────────────────────────────────────
# The same reader build/just/repo-init.just uses upstream for an archetype's
# [tokens] block: awk between the section header and the next '['.
declare -A TOK=()
while IFS= read -r line; do
    key="${line%%=*}"; key="${key// /}"
    val="$(printf '%s' "$line" | sed -n 's/^[^=]*= *"\(.*\)" *$/\1/p')"
    [ -n "$key" ] || continue
    TOK["$key"]="$val"
done < <(awk '$0=="[tokens]"{f=1;next} /^\[/{f=0} f && !/^[[:space:]]*#/ && NF' "$MANIFEST")

for required in REPO OWNER AUTHOR; do
    [ -n "${TOK[$required]:-}" ] || { echo "ERROR: $MANIFEST [tokens] has no $required" >&2; exit 2; }
done

# ─── Derived values ──────────────────────────────────────────────────────────
# DERIVABLE, never guessed — the split repo-init.just draws upstream. Each is a
# pure function of a manifest value or of the clock, so two runs of the same
# manifest on the same day agree byte for byte.
REPO="${TOK[REPO]}"; OWNER="${TOK[OWNER]}"; AUTHOR="${TOK[AUTHOR]}"
FORGE="${TOK[FORGE]:-github.com}"

TOK[PROJECT]="$(printf '%s' "$REPO" | tr '[:lower:]-' '[:upper:]_')"
TOK[project]="$(printf '%s' "$REPO" | tr '[:upper:]-' '[:lower:]_')"
TOK[AUTHOR_LAST]="${AUTHOR##* }"
TOK[AUTHOR_FIRST]="${AUTHOR% *}"
if [ "${TOK[AUTHOR_LAST]}" = "${TOK[AUTHOR_FIRST]}" ]; then
    # A single-word author name: nothing to split, and an empty surname is
    # honest where a guessed one is not.
    TOK[AUTHOR_FIRST]="$AUTHOR"; TOK[AUTHOR_LAST]=""; TOK[AUTHOR_INITIALS]=""
else
    TOK[AUTHOR_INITIALS]="${TOK[AUTHOR_FIRST]:0:1}."
fi
TOK[CURRENT_YEAR]="${TOK[CURRENT_YEAR]:-$(date +%Y)}"
TOK[CURRENT_DATE]="${TOK[CURRENT_DATE]:-$(date +%Y-%m-%d)}"
TOK[DATE]="${TOK[CURRENT_DATE]}"
TOK[EMAIL]="${TOK[AUTHOR_EMAIL]:-}"
TOK[IMAGE]="${TOK[REGISTRY]:-}/${TOK[SERVICE_NAME]:-$REPO}"

# The repo's uuid is DERIVED, not allocated (gv-clade-index identity model):
#     uuid = UUIDv5(namespace = URL, name = "<forge>/<owner>/<repo>")
# CLADE.a2ml already carries it; recomputing here is what stops the two drifting.
if command -v python3 >/dev/null 2>&1; then
    TOK[UUID]="$(python3 -c 'import sys,uuid;print(uuid.uuid5(uuid.NAMESPACE_URL,sys.argv[1]))' \
                 "${FORGE}/${OWNER}/${REPO}")"
elif command -v uuidgen >/dev/null 2>&1; then
    TOK[UUID]="$(uuidgen --sha1 --namespace @url --name "${FORGE}/${OWNER}/${REPO}" \
                 | tr '[:upper:]' '[:lower:]')"
else
    TOK[UUID]="UNASSIGNED"
fi

# Values are written into files literally, so the only thing that can corrupt
# one is a control character or a newline. Fail loudly rather than render
# something surprising. (No regex or sed metacharacter hazard exists: the
# substitution below is literal, see render_file.)
for k in "${!TOK[@]}"; do
    case "${TOK[$k]}" in
        *$'\t'*|*$'\n'*|*$'\r'*)
            echo "ERROR: token $k contains a tab or newline: ${TOK[$k]}" >&2; exit 2 ;;
    esac
done

# Longest key first: a shorter key that is a prefix of a longer one must not
# match first. (PROJECT vs PROJECT_NAME vs PROJECT_DESCRIPTION.)
TOKEN_TABLE="$(mktemp)"
cleanup() { rm -f "$TOKEN_TABLE"; }
trap cleanup EXIT
for k in $(printf '%s\n' "${!TOK[@]}" | awk '{print length, $0}' | sort -rn | cut -d' ' -f2-); do
    printf '%s\t%s\n' "$k" "${TOK[$k]}" >> "$TOKEN_TABLE"
done

if [ "$MODE" = "list" ]; then
    printf '%-26s %s\n' "TOKEN" "VALUE"
    for k in $(printf '%s\n' "${!TOK[@]}" | sort); do
        printf '%-26s %s\n' "$k" "${TOK[$k]}"
    done
    exit 0
fi

# ─── What is NOT substituted ─────────────────────────────────────────────────
# Paths excluded wholesale. Each is a template, an example, a licence text, or a
# file that NAMES tokens in order to describe or check them — rendering there
# would destroy the thing the file is for. This list is the executable form of
# issue #8's acceptance criterion: after rendering, the only brace tokens left
# are "the intentional guard/example/docs-template files".
EXCLUDE_PATHS=(
    "LICENSE"
    "LICENSES/"
    # Template-only trees. docs-template/ is the documentation seed an
    # instantiation copies FROM; machine-readable-design/ is the design
    # rationale for the template's own .machine_readable/ layout. Both are
    # marked "template-only" in .machine_readable/root-allow.txt, both are
    # already excluded from Sonar analysis and from the container build
    # context, and upstream rsr-template-repo no longer ships either.
    # Rendering them would make a template unusable as a template.
    "docs-template/"
    "machine-readable-design/"
    # Tooling that names tokens by design: the gate holds the pattern it greps
    # for, the e2e test holds the answer list it substitutes, init.just and this
    # script hold the substitution table.
    "scripts/check-no-placeholders.sh"
    "scripts/instantiate.sh"
    # The e2e instantiation test's ANSWER LIST: it names the tokens it
    # substitutes in order to assert that a fresh mint fills them. Rendering it
    # would rewrite the questions into the answers and the test would then assert
    # nothing. Upstream allowlists it for the same reason.
    "tests/e2e/template_instantiation_test.sh"
    "build/just/init.just"
    ".machine_readable/configs/instantiation.a2ml"
    # Upstream's allowlist entry: prose explaining that tokens exist.
    "EXPLAINME.adoc"
    # Machine-generated by gh actions-lock; never hand-rendered.
    ".github/workflows/actions.lock"
)

# just OWNS brace tokens inside a justfile: {{project}}, {{version}}, {{tier}},
# {{args}}, {{ARGS}}, {{recipe}} interpolate the variables the Justfile itself
# defines. A blanket pass would turn `@echo "Project: {{project}}"` into a
# literal and break every interpolating recipe. Justfile identity is fixed
# separately, at the variable definitions — see the pass near the bottom.
is_justfile() {
    case "$1" in
        Justfile|justfile|*/Justfile|*/justfile|*.just) return 0 ;;
        *) return 1 ;;
    esac
}

is_excluded() {
    local rel="$1" e
    is_justfile "$rel" && return 0
    for e in "${EXCLUDE_PATHS[@]}"; do
        case "$e" in
            */) [ "${rel#"$e"}" != "$rel" ] && return 0 ;;
            *)  [ "$rel" = "$e" ] && return 0 ;;
        esac
    done
    return 1
}

# Lines left byte-for-byte alone even inside a file that IS being rendered.
# These are the DRIFT GUARDS: methodology.a2ml's reject-if-contains and
# methodology-guard.k9.ncl's reject_patterns deliberately list the literal
# token as a pattern to REJECT. Rendering them would rewrite the guard into this
# repo's own name and silently disable the check — the hazard the k9 file's own
# comment warns about, and issue #8's first caveat.
GUARD_LINE_RE='reject-if-contains|reject_patterns'

# ─── The substitution ────────────────────────────────────────────────────────
# Literal, not regex. awk's gsub() treats its first argument as an ERE, where
# `{{` opens an interval quantifier — ugrep-based estate machines reject a bare
# doubled brace as an "empty (sub)expression", and `&` in a replacement means
# "the whole match". index()/substr() has neither hazard, so a value containing
# `.`, `*`, `[`, `&`, `\` or `|` renders exactly as written.
render_file() {
    # $1 = file to render in place, OR $1 = input  $2 = output (for --check)
    local in="$1" out="${2:-}"
    if [ -n "$out" ]; then
        awk -v table="$TOKEN_TABLE" -v guard="$GUARD_LINE_RE" '
            function litrep(s, from, to,   acc, i, n) {
                acc = ""; n = length(from)
                while ((i = index(s, from)) > 0) {
                    acc = acc substr(s, 1, i - 1) to
                    s = substr(s, i + n)
                }
                return acc s
            }
            BEGIN { while ((getline l < table) > 0) {
                        p = index(l, "\t")
                        ntok++; key[ntok] = substr(l, 1, p - 1); val[ntok] = substr(l, p + 1)
                    } }
            { if ($0 ~ guard) { print; next }
              line = $0
              for (k = 1; k <= ntok; k++) line = litrep(line, "{{" key[k] "}}", val[k])
              print line }
        ' "$in" > "$out"
    else
        local tmp; tmp="$(mktemp)"
        render_file "$in" "$tmp"
        cat "$tmp" > "$in"        # cat, not mv: preserves the file's mode bits
        rm -f "$tmp"
    fi
}

# ─── Enumerate candidate files ───────────────────────────────────────────────
# Tracked files plus untracked-but-not-ignored ones, so a newly added file is
# rendered too. `grep -I` skips binaries without needing file(1), which is not
# present on every estate machine.
mapfile -t CANDIDATES < <(
    git ls-files --cached --others --exclude-standard -z \
      | tr '\0' '\n' | grep -v '^\.git/' | sort -u
)

if [ "$MODE" = "check" ]; then
    DRIFT=0; PROBE="$(mktemp)"
    for f in "${CANDIDATES[@]}"; do
        [ -f "$f" ] || continue
        is_excluded "$f" && continue
        grep -q '{{' "$f" 2>/dev/null || continue
        grep -qI . "$f" 2>/dev/null || continue
        render_file "$f" "$PROBE"
        cmp -s "$f" "$PROBE" || { echo "  DRIFT $f" >&2; DRIFT=$((DRIFT + 1)); }
    done
    rm -f "$PROBE"
    if [ "$DRIFT" -gt 0 ]; then
        echo "instantiate --check: $DRIFT file(s) still hold renderable tokens." >&2
        echo "                     run: scripts/instantiate.sh" >&2
        exit 1
    fi
    echo "instantiate --check: tree is fully rendered."
    exit 0
fi

RENDERED=0
for f in "${CANDIDATES[@]}"; do
    [ -f "$f" ] || continue
    is_excluded "$f" && continue
    grep -q '{{' "$f" 2>/dev/null || continue
    grep -qI . "$f" 2>/dev/null || continue
    BEFORE="$(cksum < "$f")"
    render_file "$f"
    AFTER="$(cksum < "$f")"
    [ "$BEFORE" = "$AFTER" ] || { RENDERED=$((RENDERED + 1)); echo "  rendered $f"; }
done
echo "instantiate: ${RENDERED} file(s) changed."

# ─── Justfile identity ───────────────────────────────────────────────────────
# The template writes its OWN NAME as a literal, not as a token, so no
# substitution pass ever touches it. A repo scaffolded from it and never
# initialised therefore declares that it IS the template:
#
#     Justfile:22   project := "rsr-template-repo"
#     Justfile:24   REPO    := "rsr-template-repo"
#
# ...and reports its code analysis into the template's SonarCloud project.
# This is also exactly what methodology-guard.k9.ncl's state_not_template check
# rejects ("rsr-template-repo"), so the repo was failing its own drift guard.
# Upstream fixes the class with a self-name pass; here three identity lines are
# the whole exposure, so they are set exactly, and provenance lines that NAME
# the template as a parent are left alone.
for jf in Justfile .machine_readable/contractiles/Justfile; do
    [ -f "$jf" ] || continue
    sed -i -E \
        -e "s|^(project[[:space:]]*:=[[:space:]]*)\"[^\"]*\"|\1\"${TOK[project]}\"|" \
        -e "s|^(REPO[[:space:]]*:=[[:space:]]*)\"[^\"]*\"|\1\"${REPO}\"|" \
        -e "s|^(OWNER[[:space:]]*:=[[:space:]]*)\"[^\"]*\"|\1\"${OWNER}\"|" \
        "$jf"
done
echo "instantiate: Justfile identity set to ${TOK[project]} / ${OWNER} / ${REPO}."

# ─── Self-name pass ──────────────────────────────────────────────────────────
# The template writes its OWN NAME as a literal, not as a token, so no
# substitution pass above ever touched it. Left alone, an instantiated repo
# keeps declaring that it IS the template — in prose, in CI output, in the
# coaptation receipt, and in the contractiles' own titles. methodology.a2ml
# rejects "rsr-template-repo" in STATE.a2ml for exactly this reason, and
# methodology-guard.k9.ncl repeats it: the repo was failing its own drift guard.
#
# PROVENANCE MUST SURVIVE. A minted repo is supposed to record what it came
# from, and several files legitimately point AT the template: the ADR that
# adopts it, the audit that measures against it, the dogfood gate that tells you
# where to copy a repo deed from, the a2ml validator whose comments compare this
# tree to the template's. Two protections, both taken from upstream's own
# self-name pass in build/just/repo-init.just:
#   * paths that are ABOUT the template are skipped wholesale;
#   * within every other file, a line that names the parent AS a parent is left
#     byte-for-byte alone.
SELF_PROV='instantiated-from|parent|upstream|chain =|lineage|minted from|created from|Template: |Copy one from|Generated by|survive as-is|is not init tokens|not an init token'
SELF_NAME_EXCLUDE=(
    "build/just/init.just"                 # holds the literal to describe the defect
    "scripts/instantiate.sh"               # this pass
    "scripts/check-no-placeholders.sh"     # the gate's own commentary
    "docs/decisions/"                      # ADR-0001 IS "adopt rsr-template-repo"
    "docs/governance/TEMPLATE-STANDARDS-AUDIT.adoc"
    "docs/governance/CRG-AUDIT-TEMPLATE.adoc"
    "docs/governance/TEMPLATE-LINEAGE-AUDIT.adoc"
    "CHANGELOG.adoc"
    ".github/workflows/dogfood-gate.yml"   # tells you to copy a deed FROM the template
    ".githooks/validate-a2ml.sh"           # comments compare this tree to the template's
    # The RSR template VALIDATOR: it is about the template by definition, and its
    # Phase 5 commentary quotes the template's own basename test verbatim to
    # explain why that test was wrong. Rewriting the quote turned the explanation
    # into nonsense on the second pass — this list is what makes the pass
    # idempotent for files that discuss the parent.
    "scripts/validate-template.sh"
    ".machine_readable/contractiles/README.adoc"
    ".machine_readable/bot_directives/methodology.a2ml"     # reject-pattern guard
    ".machine_readable/self-validating/methodology-guard.k9.ncl"
    ".machine_readable/self-validating/examples/"           # illustrative examples
    # The 6a2 -> descriptiles migration notes NAME the template and standards as
    # the source of the canonical path. Rewriting them turned "the path
    # rsr-template-repo and standards both use" into a claim about this repo.
    ".machine_readable/descriptiles/README.adoc"
    ".machine_readable/descriptiles/0-AI-MANIFEST.a2ml"
)

self_name_excluded() {
    local rel="$1" e
    for e in "${SELF_NAME_EXCLUDE[@]}"; do
        case "$e" in
            */) [ "${rel#"$e"}" != "$rel" ] && return 0 ;;
            *)  [ "$rel" = "$e" ] && return 0 ;;
        esac
    done
    return 1
}

if [ "$MODE" != "check" ] && [ "$REPO" != "rsr-template-repo" ]; then
    SELF_REWRITTEN=0
    for f in "${CANDIDATES[@]}"; do
        [ -f "$f" ] || continue
        self_name_excluded "$f" && continue
        # A justfile is excluded from TOKEN substitution (just owns its brace
        # interpolation) but not from this pass: `@echo "=== rsr-template-repo
        # Tour ==="` is a plain string literal and leaving it makes the recipe
        # announce the wrong project. Guard per line instead — a line carrying a
        # brace token is just's, not ours.
        if ! is_justfile "$f"; then
            is_excluded "$f" && continue
        fi
        grep -q 'rsr-template-repo' "$f" 2>/dev/null || continue
        grep -qI . "$f" 2>/dev/null || continue
        BEFORE="$(cksum < "$f")"
        # `/\{\{/` skips any line holding a brace token: in a justfile that is
        # just's own interpolation and must not be touched.
        sed -i -E "/${SELF_PROV}/!{/\{\{/!{s|hyperpolymath/rsr-template-repo|${OWNER}/${REPO}|g;s|rsr-template-repo|${REPO}|g;}}" "$f"
        AFTER="$(cksum < "$f")"
        [ "$BEFORE" = "$AFTER" ] || { SELF_REWRITTEN=$((SELF_REWRITTEN + 1)); echo "  self-name $f"; }
    done
    echo "instantiate: self-name pass rewrote ${SELF_REWRITTEN} file(s) (provenance lines preserved)."
fi

# ─── Verify ──────────────────────────────────────────────────────────────────
if [ "$MODE" = "render+verify" ]; then
    echo ""
    if [ -f "$GATE" ]; then
        bash "$GATE" . || exit 1
    else
        echo "WARN: $GATE missing — rendered but unverified." >&2
    fi
fi
