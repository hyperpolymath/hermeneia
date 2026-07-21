<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk> -->

# Architecture

Hermeneia is the **voking / query layer** of the trope stack. It compiles voke
expressions into Trope IR and delegates every p-sufficiency verdict to
`trope-checker`, while owning query planning, store traversal, path composition,
and licence state itself.

- Why the language exists, and its formal semantics — [`docs/THEORY.adoc`](docs/THEORY.adoc)
- How it binds to the rest of the stack — [`docs/SPEC.adoc`](docs/SPEC.adoc)

This file is the map. The two documents above are the territory.

## Position in the stack

```
trope-particularity-workbench   normative vocabulary
trope-checker                   decidable core (Idris2 reference + Rust fast core)
haec                            transformation language; emits Trope IR
vocarium                        the store of vokeable particulars
hermeneia                       the voking / query language        <-- here
```

Chain: `Vocarium (store) → Hermeneia (voke)`, and
`Haec (transform) → Hermeneia (query over transformed particulars)`.

## The central rule

**Hermeneia does not implement the grade algebra.** That algebra is proved in
Idris2 inside `trope-checker`; a second implementation here would fork the exact
semantics the design exists to protect. Hermeneia emits Trope IR v0.2 and reads
back a verdict.

It is not, however, a wrapper around the checker: only three of the seven voking
operations need a verdict at all.

| Operation | Owner | Needs a verdict? |
|---|---|---|
| `invoke` | core → checker | yes |
| `provoke` | core → checker | yes |
| `intervoke` | core → checker | yes (one per branch) |
| `evoke` | store traversal | no |
| `convoke` | store traversal | no |
| `transvoke` | path composition | only if asked |
| `revoke` | licence state | no |

## Query pipeline

```
.hil source
   │  hermeneia-syntax    lex, parse, AST
   ▼
 voke expression
   │  hermeneia-core      plan; resolve use-model to a floor
   ▼
 store access
   │  hermeneia-store     StoreProvider (JSONL stub now; Vocarium later)
   ▼
 transformation path
   │  hermeneia-ir        emit Trope IR v0.2; validate against the schema
   ▼
 tropecheck <ir.json>     verdict + witness edge + coordinate
   │  hermeneia-cli
   ▼
 rendered result
```

## Layout

```
src/hermeneia-syntax/    .hil lexer, parser, AST
src/hermeneia-core/      voke operations, planner, licence state
src/hermeneia-store/     StoreProvider trait + JSONL stub + seed corpus
src/hermeneia-ir/        Trope IR v0.2 emitter
src/hermeneia-cli/       `hermeneia query …`
verification/proofs/idris2/Voke/   voke algebra laws
docs/THEORY.adoc         the contribution, implementation-independent
docs/SPEC.adoc           the applied binding and integration contract
```

## The store seam

Vocarium does not exist yet, so hermeneia ships a JSONL stub behind a narrow
trait (`StoreProvider`) with the README's own worked example as the seed corpus.
Vocarium substitutes in without the planner changing. The trait is specified in
[`docs/SPEC.adoc`](docs/SPEC.adoc).

## Validation

`trope-checker/tests/conformance/` provides a golden corpus of IR fixtures with
expected verdicts, witnesses, and coordinates. Hermeneia's emitter is validated
by round-trip against it — the same oracle that validates the Rust fast core
against the Idris2 reference.

## Known constraint

`tropecheck` prints only the verdict plus a single witness edge and coordinate.
It does **not** emit the per-dimension loss vector that `README.adoc` shows under
`show loss`, even though the checker computes the full violated-coordinate list
internally. Slice v1 therefore implements `show verdict`, not `show loss`. See
[`docs/SPEC.adoc`](docs/SPEC.adoc) for the detail and the proposed remedy.
