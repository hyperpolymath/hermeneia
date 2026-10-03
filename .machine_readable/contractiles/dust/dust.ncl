# SPDX-License-Identifier: MPL-2.0
# Dust — Hermeneia generated-output cleanup and retirement runner schema
#
# Pairs with: Dustfile.a2ml (same directory)
# Verb:       dust
# Semantics:  advisory cleanup proposals; destructive actions default to dry
#             run and require explicit per-item maintainer approval.
#
# The compatible contractile CLI is not bundled in this repository. The
# `--apply` shape below is a future runner policy, not an available command.
# See: .machine_readable/contractiles/README.adoc

let base = import "../_base.ncl" in

{
  pedigree = base.pedigree_schema & {
    contractile_verb = "dust",
    semantics = "safe cleanup and exnovation with history/evidence/rollback preservation",
    security = {
      leash = 'Kennel,
      trust_level = "read-only discovery; future apply requires explicit approval",
      allow_network = false,
      allow_filesystem_write_conditional = true,
      allow_subprocess = true,
      destructive_mode_requires_flag = "--apply",
    },
    metadata = {
      name = "dust-runner",
      version = "1.1.0",
      description = "Lists declared Hermeneia generated-output candidates; future destructive actions require dry-run review, --apply, and per-item approval.",
      paired_xfile = "Dustfile.a2ml",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  schema = {
    removal_candidates
      | Array {
          id | String,
          description | String,
          target | String,
          reason | String,
          probe | String | optional,
          status | [| 'declared, 'proposed, 'approved, 'removed |] | default = 'declared,
          approver | String | optional,
          notes | String | optional,
        },
  },

  run = base.run_defaults & {
    on_any_fail = "continue-with-warnings",
    report_format = "a2ml",
    emit_summary = true,
    apply_requires_approval = true,
  },
}
