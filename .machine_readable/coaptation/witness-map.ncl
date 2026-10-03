# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# witness-map.ncl — the KNOWLEDGE layer of Coaptation (step 2 of the build path).
#
# Declares, for the clauses that CAN be witnessed by descriptive evidence, which
# descriptile fact(s) bear that witness and under what predicate. This is the one
# hand-authored, human-reviewable file in the pack: it encodes the correspondence
# between a normative obligation (a contractile clause) and the descriptive facts
# that attest it.
#
# A clause NOT listed here is graded automatically by the comparator:
#   - it has a runnable probe        -> "probe-deferred" (only Hunt can judge it)
#   - it has neither witness nor probe -> "unmeasured" (a real Yard coverage hole)
#
# Predicate ops (over a fact's value/present):
#   'present | 'absent | 'zero | 'nonzero | 'equals | 'contains | 'not_contains
# 'equals/'contains/'not_contains take `arg`. A clause's witnesses ALL must hold.
#
# Soundness-critical entries (the Must/Trust gates) are the ones to graduate to
# Idris2 `Witnesses` proofs in a later session (build-path step 6); today they are
# declarative. Keep this list HONEST: only assert a witness you can defend — the
# whole point is to make boundary-erosion visible, not to manufacture green.
{
  # --- MUST: presence obligations attested by the fact that we parsed the file ---
  "must.machine-readable-dir" = {
    kind = "descriptile",
    witnesses = [ { fact = "state.status", op = 'present } ],
    note = "descriptiles parse ⇒ .machine_readable/ exists and is populated",
  },
  "must.six-directory-present" = {
    kind = "descriptile",
    witnesses = [
      { fact = "state.phase", op = 'present },
      { fact = "ecosystem.type", op = 'present },
    ],
    note = "STATE.a2ml + ECOSYSTEM.a2ml were read from .machine_readable/descriptiles/",
  },
  "must.anchors-directory" = {
    kind = "descriptile",
    witnesses = [ { fact = "anchor.authority", op = 'present } ],
    note = "ANCHOR.a2ml was read from .machine_readable/descriptiles/anchors/",
  },

  # --- TRUST: deliberately NO descriptile witness. ---
  # Every Trust obligation here (no-secrets / no-private-keys / author-correct /
  # license-content / …) is a filesystem-or-git probe. The descriptive self-model
  # carries NO security/provenance evidence that can attest them in the Yard tier,
  # so they are all reported `probe-deferred` and need a Hunt run. We do NOT witness
  # `trust.author-correct` with `clade.forge-github` — forge OWNERSHIP is not git
  # AUTHORSHIP, and resting a Trust gate on that proxy would be a manufactured green.
  # The `boolean_gate_provenance` grade (a witness carrying its source hash) is a
  # declared capability awaiting a descriptile that actually carries such evidence.

  # --- INTEND: a committed intent realised by the descriptive self-model ---
  # Was: witness `ecosystem.type equals "repository-template"`, i.e. this clause
  # was attested by ECOSYSTEM declaring that the repo IS the RSR template.
  # hermeneia's ECOSYSTEM.a2ml says type = "query-language", so the witness was
  # permanently REFUTED — the receipt grades intend.repo-initialization against a
  # fact about a different project. Intentfile's clause was restated at
  # instantiation (issue #8) to mean "this repo is rendered from its template and
  # has not drifted back", which is what the anchor can actually attest: an
  # un-substituted ANCHOR identity is the visible symptom of an un-instantiated
  # repo, and a rendered one is the symptom of the intent being met.
  "intend.repo-initialization" = {
    kind = "descriptile",
    witnesses = [ { fact = "anchor.project", op = 'not_contains, arg = "{{" } ],
    note = "ANCHOR.identity.project is rendered (no brace token) ⇒ the repo is instantiated, not a template",
  },

  # --- ADJUST: accessibility/hygiene posture (advisory; never gates) ---
  # The substitution pass rendered the NOTE's parenthetical, which left this
  # saying "ANCHOR.identity.project is un-substituted (Hermeneia) ⇒ posture dip"
  # — a witness that now HOLDS annotated as a dip. A note that contradicts its own
  # predicate is how a green reading gets trusted for the wrong reason.
  "adjust.placeholder-drift" = {
    kind = "descriptile",
    witnesses = [ { fact = "anchor.project", op = 'not_contains, arg = "{{" } ],
    note = "ANCHOR.identity.project carries no brace token ⇒ no placeholder drift; posture OK",
  },

  # --- BUST: recognised break. For bust, a HOLDING witness means ALARM (active
  #     failure), not satisfaction. open-failures/last-result are the live signal. ---
  "bust.template-substitution-failure" = {
    kind = "descriptile",
    witnesses = [ { fact = "state.open-failures", op = 'nonzero } ],
    note = "alarm iff STATE records open failures; else latent (declared, not active)",
  },
  "bust.sync-drift-between-repos" = {
    kind = "descriptile",
    witnesses = [ { fact = "state.open-failures", op = 'nonzero } ],
    note = "alarm iff STATE records open failures; else latent",
  },
  "bust.contractile-parse-error" = {
    kind = "descriptile",
    witnesses = [ { fact = "state.last-result", op = 'equals, arg = "fail" } ],
    note = "alarm iff the last maintenance run failed; else latent",
  },
}
