# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# INIT — instantiate this repository from its template placeholders.
#
# Imported by ../../Justfile via `import? "build/just/init.just"`. Variables
# (project, OWNER, REPO, version, tier) and the `set shell` directive are
# inherited from the root Justfile.
#
# ─── WHY THIS FILE EXISTS ─────────────────────────────────────────────────────
# The root Justfile has imported this path since the repo was scaffolded, and the
# file was never here. `import?` is an OPTIONAL import: just silently ignores a
# missing module, so `just init` did not fail — it reported "No such recipe" or,
# worse, nothing at all. That silence is the actual root cause of issue #8: ~120
# files shipped as an unrendered template because the one command that would have
# rendered them had no body, and no gate noticed the body was missing.
#
# Upstream hyperpolymath/rsr-template-repo ships this as build/just/repo-init.just
# and has renamed the recipe `repo-init`. It is a MINT recipe: archetype
# overlays, a docs-seed, deed splicing, provenance rewriting, a clade choice.
# None of that applies to a repository that already exists, already has its deed
# identity, and already has real content in docs/. Copying it here would ship
# 900 lines that reference archetypes/, build/docs-seed/, build/templates/ and
# scripts/rust-tool.sh — none of which this repo has — and every one of which
# would fail on first run.
#
# So this is the narrow, honest equivalent: render the tokens, from committed
# values, and prove the result. The engine is scripts/instantiate.sh (plain bash,
# runnable without just, which matters because CI images do not all carry it) and
# the values are .machine_readable/configs/instantiation.a2ml.
#
# The gate is scripts/check-no-placeholders.sh, vendored verbatim from upstream
# so this repo and the template cannot drift on what "unfilled" means.

# Render every {{PLACEHOLDER}} token from .machine_readable/configs/instantiation.a2ml
init:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "════════════════════════════════════════════════════════════"
    echo "  Hermeneia — template instantiation"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "  project   {{project}}"
    echo "  owner     {{OWNER}}"
    echo "  repo      {{REPO}}"
    echo "  values    .machine_readable/configs/instantiation.a2ml"
    echo ""
    bash scripts/instantiate.sh
    echo ""
    echo "Next: git diff   (review what was rendered)"

# Verify the tree is fully rendered without changing anything. Exit 1 on drift.
init-check:
    #!/usr/bin/env bash
    set -euo pipefail
    bash scripts/instantiate.sh --check
    bash scripts/check-no-placeholders.sh .

# Print the resolved token table, including the values this script derives.
init-list:
    @bash scripts/instantiate.sh --list

# Run the estate placeholder gate alone (the check openssf-compliance.yml runs).
placeholders:
    @bash scripts/check-no-placeholders.sh .
