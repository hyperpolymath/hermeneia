# SPDX-License-Identifier: MPL-2.0
# Bust — Hermeneia fail-closed stop-condition runner schema
#
# Pairs with: Bustfile.a2ml (same directory)
# Verb:       bust
# Semantics:  synthetic repository-local regression probes for cases where
#             Hermeneia must stop rather than emit success or fabricated output.
#             No user data or external system is a probe target.
#
# The compatible contractile CLI is not bundled here. The Rust unit suite and
# oracle-backed slice workflow are the currently wired executable evidence.
# See: .machine_readable/contractiles/README.adoc

let base = import "../_base.ncl" in

{
  pedigree = base.pedigree_schema & {
    contractile_verb = "bust",
    semantics = "fail-closed stop conditions for unsupported operations, malformed data, oracle faults, and fabricated output",
    security = {
      leash = 'Kennel,
      trust_level = "synthetic repository-local regression tests",
      allow_network = false,
      allow_filesystem_write = true,
      allow_subprocess = true,
      injection_scope = "checked-in-test-fixtures-only",
    },
    metadata = {
      name = "bust-runner",
      version = "1.1.0",
      description = "Declares isolated regression tests for stop conditions; does not inject faults into user data or external systems.",
      paired_xfile = "Bustfile.a2ml",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  schema = {
    failure_modes
      | Array {
          id | String,
          description | String,
          class | [| 'network, 'disk_full, 'oom, 'timeout, 'partial_write, 'panic, 'crash, 'rollback, 'concurrency, 'unsupported_operation, 'oracle_unavailable, 'malformed_input, 'false_license |],
          injection_probe | String,
          recovery_probe | String,
          expected_recovery_time_seconds | Number | default = 30,
          status | [| 'declared, 'drilled, 'verified, 'failing |] | default = 'declared,
          notes | String | optional,
        },
  },

  run = base.run_defaults & {
    on_any_fail = "exit-nonzero",
    report_format = "a2ml",
    emit_summary = true,
    record_recovery_times = true,
  },
}
