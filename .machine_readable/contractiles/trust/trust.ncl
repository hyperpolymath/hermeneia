# SPDX-License-Identifier: MPL-2.0
# Trust — Hermeneia trust-boundary and integrity runner schema
#
# Pairs with: Trustfile.a2ml (same directory)
# Verb:       trust
# Semantics:  intended hard gate over local inputs, provenance limits, and
#             fail-closed handling. No active external safe-hacking target is
#             authorized by the current project draft.
#
# This file declares the expected schema; the compatible contractile CLI is not
# bundled. Rust, secret-scanner, and slice workflows are the wired evidence.
#
# Base: ../_base.ncl provides pedigree_schema, run_defaults, probe_schema.
# See: .machine_readable/contractiles/README.adoc

let base = import "../_base.ncl" in

{
  pedigree = base.pedigree_schema & {
    contractile_verb = "trust",
    semantics = "untrusted inputs, provenance limits, and fail-closed behavior",
    security = {
      leash = 'Kennel,
      trust_level = "read-only repository-local verification",
      allow_network = false,
      allow_filesystem_write = false,
      allow_subprocess = true,
      authorised_probes_only = true,
    },
    metadata = {
      name = "trust-runner",
      version = "1.1.0",
      description = "Declares local input-integrity and fail-closed checks; no network service or active external penetration test is authorized.",
      paired_xfile = "Trustfile.a2ml",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  schema = {
    verifications
      | Array {
          id | String,
          description | String,
          probe | String,
          status | [| 'declared, 'verified, 'failing |] | default = 'declared,
          severity | [| 'critical, 'high, 'medium, 'low |] | default = 'high,
          notes | String | optional,
        },

    # This mechanism remains available for a future, explicitly approved,
    # repository-local test plan. The current Trustfile authorizes no active
    # fuzzing, chaos, auth-bypass, injection, timing, or network probe.
    safe_hacking
      | {
          scope | String,
          allowed_probe_classes
            | Array [| 'fuzz, 'property_test, 'chaos, 'auth_bypass, 'injection, 'timing |]
            | default = [],
          probes
            | Array {
                id | String,
                class | [| 'fuzz, 'property_test, 'chaos, 'auth_bypass, 'injection, 'timing |],
                description | String,
                probe | String,
                expected_outcome | [| 'probe_blocks_attempt, 'probe_finds_no_issue |],
                timeout_seconds | Number | default = 300,
                notes | String | optional,
              }
            | default = [],
        }
      | default = { scope = "this-repo-only", allowed_probe_classes = [], probes = [] },
  },

  run = base.run_defaults & {
    on_any_fail = "exit-nonzero",
    safe_hacking_on_unexpected_outcome = "exit-nonzero",
    report_format = "a2ml",
    emit_summary = true,
  },
}
