# SPDX-License-Identifier: MPL-2.0
# Must — Hermeneia invariants runner schema
#
# Pairs with: Mustfile.a2ml (same directory)
# Verb:       must
# Semantics:  intended hard gate for repository invariants and evidence.
#
# This declares the expected schema and authority. The compatible contractile
# executable is not bundled in this repository, so no `must check` CLI command
# is currently wired. scripts/verify-contractiles.sh checks only structure and
# manifest integrity; Rust and GitHub workflow probes are listed separately in
# the declaration.
#
# Base: ../_base.ncl provides pedigree_schema, run_defaults, probe_schema.
# See: .machine_readable/contractiles/README.adoc

let base = import "../_base.ncl" in

{
  pedigree = base.pedigree_schema & {
    contractile_verb = "must",
    semantics = "Hermeneia repository, test, and evidence-boundary invariants",
    security = {
      leash = 'Kennel,
      trust_level = "read-only verification",
      allow_network = false,
      allow_filesystem_write = false,
      allow_subprocess = true,
    },
    metadata = {
      name = "must-runner",
      version = "1.1.0",
      description = "Declares intended release-blocking repository and evidence invariants; only the explicitly named GitHub workflow probes are currently wired.",
      paired_xfile = "Mustfile.a2ml",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  schema = {
    invariants
      | Array {
          id | String,
          description | String,
          probe | String,
          status | [| 'declared, 'verified, 'failing |] | default = 'declared,
          severity | [| 'critical, 'high, 'medium |] | default = 'critical,
          notes | String | optional,
          fix | String | optional,
        },
  },

  run = base.run_defaults & {
    on_any_fail = "exit-nonzero",
    report_format = "a2ml",
    emit_summary = true,
  },
}
