# SPDX-License-Identifier: MPL-2.0
# Intend — Hermeneia north-star, commitments, and aspirations runner schema
#
# Pairs with: Intentfile.a2ml (same directory)
# Verb:       intend
# Semantics:  reports committed-action status and groups non-probeable wishes
#             by horizon. Reporting authority only; never blocks a build.
#
# The compatible contractile CLI is not bundled in this repository. This is a
# declaration of the intended runner schema, not evidence that probes execute.
# The historical `lust` schema was absorbed into `intend`; there is no current
# `lust/` trident.
#
# Base: ../_base.ncl provides pedigree_schema, run_defaults, probe_schema.
# See: .machine_readable/contractiles/README.adoc

let base = import "../_base.ncl" in

{
  pedigree = base.pedigree_schema & {
    contractile_verb = "intend",
    semantics = "Hermeneia purpose, implemented scope, committed actions, and wishes",
    security = {
      leash = 'Kennel,
      trust_level = "read-only reporting",
      allow_network = false,
      allow_filesystem_write = false,
      allow_subprocess = true,
    },
    metadata = {
      name = "intend-runner",
      version = "2.1.0",
      description = "Reports progress toward Hermeneia's declared project actions and groups future wishes. Non-gating; compatible runner CLI is not bundled.",
      paired_xfile = "Intentfile.a2ml",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  schema = {
    intents
      | Array {
          id | String,
          description | String,
          probe | String | optional,
          status | [| 'declared, 'in_progress, 'done, 'deferred, 'retired |] | default = 'declared,
          notes | String | optional,
          target_date | String | optional,
        },
    wishes
      | Array {
          id | String,
          description | String,
          horizon | [| 'near, 'mid, 'far |] | default = 'mid,
          why | String | optional,
          status | [| 'declared, 'in_progress, 'achieved, 'abandoned |] | default = 'declared,
          notes | String | optional,
        }
      | optional,
  },

  run = base.run_defaults & {
    on_pass = "continue",
    on_any_fail = "continue",
    report_format = "a2ml",
    emit_summary = true,
    emit_diff = true,
    emit_grouped_by_horizon = true,
  },
}
