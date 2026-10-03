# SPDX-License-Identifier: MPL-2.0
# Adjust — advisory accessibility, clarity, and drift-tolerance runner
#
# Pairs with: Adjustfile.a2ml (same directory)
# Verb:       adjust
# Semantics:  advisory tolerance review for the current text CLI and its
#             implementation-status claims. It is not a WCAG checker.
#
# The declaration schema uses tolerance/corrective language. Corrective
# actions are recommendations; no file-writing fix is authorized by default.
# The compatible contractile CLI is not bundled in this repository.
#
# Base: ../_base.ncl provides pedigree_schema, run_defaults, probe_schema.
# See: .machine_readable/contractiles/README.adoc

let base = import "../_base.ncl" in

{
  pedigree = base.pedigree_schema & {
    contractile_verb = "adjust",
    semantics = "advisory accessibility, diagnostic clarity, and evidence-boundary tolerances",
    security = {
      leash = 'Kennel,
      trust_level = "read-only evaluation; human-reviewed recommendations",
      allow_network = false,
      allow_filesystem_write = false,
      allow_subprocess = true,
    },
    metadata = {
      name = "adjust-runner",
      version = "1.1.0",
      description = "Measures advisory Hermeneia text-CLI and documentation tolerances; proposes, but does not automatically apply, corrective actions.",
      paired_xfile = "Adjustfile.a2ml",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  schema = {
    requirements
      | Array {
          id | String,
          description | String,
          tolerance | String,
          corrective | String,
          probe | String | optional,
          status | [| 'declared, 'partial, 'verified, 'failing |] | default = 'declared,
          severity | [| 'critical, 'high, 'medium, 'low, 'advisory |] | default = 'advisory,
          notes | String | optional,
          fix | String | optional,
        },
  },

  # Adjust is advisory. Corrective commands remain human-reviewed; the runner
  # does not write to the worktree in this project-specific draft.
  run = base.run_defaults & {
    on_any_fail = "continue-with-warnings",
    report_format = "a2ml",
    emit_summary = true,
    auto_fix_when_available = false,
  },
}
