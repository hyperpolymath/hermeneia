K9!
# SPDX-License-Identifier: MPL-2.0
# trust.k9.ncl — K9 trust-tier component of the trust trident
# Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Pairs with: Trustfile.a2ml (declaration) + trust.ncl (runner).
# The trust boundary in this project is a local command-line program, not a
# web service. Query text, JSONL records, IR, and checker output are untrusted;
# grades/warrants do not establish semantic truth. The external tropecheck
# executable is the sole grade-algebra oracle.
#
# Verb:       trust           (security boundary + provenance + fail-closed)
# Tier:       Hunt            (repository-local subprocess checks only)
# Authority:  blocking        (intended hard gate; runtime integration pending)
#
# Cardinality: one trust trident per repository. The project-specific trust
# clauses below are provisional until maintainer review. The hooks, variance
# workflow, and evidence-sink configuration describe a future compatible
# runner profile; they are not claims that this checkout executes them.
#
# No network-facing target or active safe-hacking probe is authorized by the
# current Trustfile. An optional VeriSimDB feed declaration exists elsewhere
# in .machine_readable/ but no writer was found; decide before enabling it.
# The separate K9 validator failure remains untouched.

let base    = import "../_base.ncl" in

{
  pedigree = base.pedigree_schema & {
    name = "trust.k9.ncl",
    component_type = "hermeneia-contractile",
    schema_version = "1.0.0",
    contractile_verb = "trust",
    paired_xfile     = "../trust/Trustfile.a2ml",
    paired_runner    = "../trust/trust.ncl",

    # Capability and authority remain separate axes. Hunt permits the
    # declared local subprocess checks; it does not authorize network or
    # external probes. Blocking is the intended policy for trust failures,
    # while the compatible contractile runtime is still absent.
    tier      = 'Hunt,
    authority = 'blocking,

    metadata = {
      name = "trust-k9",
      version = "1.1.0",
      description = "Declares Hermeneia's local-input, provenance, and fail-closed trust policy. Intended blocking authority; no active external probe or bundled contractile runtime.",
      paired_xfile = "Trustfile.a2ml",
      paired_runner = "trust.ncl",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },

    security = {
      leash = 'Hunt,
      signature_required = true,
      trust_level = "repository-local read-only checks; intended hard-gate authority",
      allow_network = false,            # verifications offline by default
      allow_filesystem_write = false,   # evidence sinks are indirected
      allow_subprocess = true,
      authorised_probes_only = true,    # probe section explicitly lists allowed targets + probe classes
      probe_scope_enforcement = 'this_repo_only,  # probes NEVER hit external systems
    },
  },

  # -------------------------------------------------------------------
  # Variance schema — P-shape scoped exceptions per verification.
  # A variance suppresses a specific verification's obligation for a
  # reason, with approver + expiry. Because trust is BLOCKING authority,
  # variances on trust entries are SIGNIFICANTLY more consequential than
  # variances on intend (reporting) entries — variance approver MUST
  # be the repo maintainer or above for critical-severity entries.
  # -------------------------------------------------------------------
  variance_schema = {
    entry_id     | String,   # which verification / probe id
    reason       | String,
    approved_by  | String,   # maintainer or above for critical entries
    scope        | String,   # path glob | session-id | "until-<date>"
    expires      | String,   # absolute date; trust variances cannot be open-ended
    review_notes | String | optional,
    # Additional trust-specific guardrails:
    severity_acknowledged | [| 'critical, 'high, 'medium, 'low |],
    waived_risk_description | String,  # plain language — what is being accepted
  },

  # -------------------------------------------------------------------
  # Execution policy
  # -------------------------------------------------------------------
  execution = {
    # When the component runs.
    # pre_push + pre_commit on anything touching security-adjacent files
    # + session_close (drift check) + on_demand.
    triggers = [ 'session_close, 'on_demand, 'pre_push, 'pre_commit_security_adjacent ],

    # Per-verification execution. Failed verification = blocked merge.
    per_verification = {
      run_probe = true,
      record_outcome = true,
      respect_variance = true,    # active variance suppresses the gate
      on_unmet = 'fail,           # BLOCKING — the opposite of intend's 'log_drift
      severity_escalation = 'honour,  # critical > high > medium > low in gate decisions
    },

  # Per-safe-hacking-probe policy for a future explicitly approved local
  # test plan. The current Trustfile declares no active probes. If probes
  # are later approved, only their expected outcome and local scope apply.
    per_probe = {
      run_probe = true,
      record_outcome = true,
      honour_expected_outcome = true,
      on_unexpected_exploit_success = 'fail,  # exploit found where it shouldn't be
      scope_enforcement = 'this_repo_only,    # never touch external systems
      timeout_honouring = 'strict,
    },

    # Target evidence sinks for a future compatible runner. Neither is
    # currently written here. In particular, the VeriSimDB target must remain
    # inactive until the optional feed is explicitly owner-approved.
    evidence_sinks = [
      {
        kind   = 'verisimdb,
        table  = "contractile_executions",
        schema = "contractile_execution_v1",
        # trust-specific sub-table for probe outcomes (for threat-model audit)
        aux_tables = [ "trust_verifications", "trust_probes" ],
      },
      {
        kind        = 'drift_log,
        path        = ".machine_readable/descriptiles/DRIFT.a2ml",
        append_only = true,
      },
    ],

    # Proposed session-close review: repeat the declared local checks and
    # compare them with the reviewed baseline. This hook is not currently
    # connected to an installed runner or GitHub session lifecycle.
    on_close = {
      re_execute_all_verifications = true,
      re_run_all_safe_hacking_probes = true,
      diff_against_last_ratification = true,
      emit_drift_entries_for_new_failures = true,
      surface_expired_variances = true,
      # trust-specific: if any blocking-severity verification is newly
      # failing, the session close is BLOCKED from completing. User
      # cannot close a session with unresolved critical trust drift.
      block_session_close_on_critical_drift = true,
    },

    # -----------------------------------------------------------------
    # Session-open hook — NEGOTIATION + RATIFICATION + ACCOUNTABILITY
    # (inherited shape from intend.k9.ncl v2.0.0; trust-specific
    # additions around threat-model foregrounding below)
    # -----------------------------------------------------------------
    on_open = {
      # --- Context presentation ---
      render_summary = 'plain_language,    # metaphor-capture defense
      include_drift_log_from_last_close = true,
      include_active_variances = true,
      include_recent_anchors = true,
      anchor_lookback_weeks = 8,

      # Render the project boundary before any proposed trust-policy change:
      # local CLI, untrusted query/data/IR/oracle inputs, and no approved
      # network-facing target. This avoids importing unrelated web-service
      # assumptions into a trust decision.
      threat_model_foregrounding = {
        required = true,
        render_adversaries = true,   # from the Trustfile Threat Model section
        render_stakes = true,
        render_compliance_regimes = true,
        render_audience_sensitivity = true,
        # If the AI is about to suggest a trust-weakening action, it
        # must re-render the threat model before the suggestion lands.
        re_render_before_weakening_suggestion = true,
      },

      # --- Negotiation phase (five mandatory inputs, inherited) ---
      negotiation = {
        required = true,
        ai_required_inputs = [
          'timeline_realism,
          'industry_standards,        # identify only standards that actually apply; do not invent regimes for a local CLI
          'audience_feasibility,      # who is the adversary? who is protected?
          'resulting_invariants,      # what trust entries the work creates/amends
          'ecosystem_dependencies,    # local JSONL store and the external tropecheck executable
        ],
        user_engagement_required = true,
        user_engagement_mode = 'per_input_response,
        specification_translation = {
          ai_produces_spec_form = true,
          user_reviews_in_domain_language = true,
          schema_authoring_is_ai_responsibility = true,
          translation_faithfulness_auditable = true,
          # Trust-specific translation should explain the local data flow,
          # parser/IR validation, checker failure behavior, and limits of the
          # supplied grades without requiring the maintainer to author Nickel.
        },
      },

      # --- Accountability pledge (both parties, explicit) ---
      # trust's pledge is MORE stringent than intend's because the
      # authority is blocking. A user accepting accountability here is
      # accepting that security-affecting decisions have blocking consequence.
      accountability_pledge = {
        required = true,
        parties = [
          {
            role = 'user,
            pledge = "I have reviewed the local CLI trust boundary, the untrusted query/data/IR/oracle inputs, and the stated limits on grades and warrants. I understand the proposed blocking authority and will approve any expansion to network, remote-store, credential, or destructive scope explicitly rather than by implication.",
            signature_required = true,
          },
          {
            role = 'ai_agent,
            pledge = "I will treat Hermeneia's query text, JSONL, IR, and checker output as untrusted; preserve the checker as the sole grade-algebra oracle; and refuse to turn a missing checker or malformed evidence into a successful verdict. I will not add network, remote-store, credential, or destructive behavior without explicit maintainer approval and a reviewed amendment.",
            signature_required = true,
          },
        ],
        signed_record_destination = ".machine_readable/descriptiles/ratification-<session-id>.a2ml",
        must_precede_work = true,
      },

      ratification_record_shape = {
        includes_negotiation_transcript = true,
        includes_both_pledges = true,
        includes_threat_model_snapshot = true,   # trust-specific
        signed = true,
        dated = true,
        session_id = 'required,
        contract_hash = 'required,
      },
    },
  },

  # -------------------------------------------------------------------
  # Project-specific failure-mode categories retained as policy labels. They
  # are not a reference to an external executable catalog.
  # -------------------------------------------------------------------
  failure_mode_defenses = [
    # Category A — enthusiasm / narrative capture
    'A1_enthusiasm_capture,            # scope breach blocks via blocking authority
    'A2_metaphor_capture,              # render_summary + re_render_before_weakening
    # Category B — threat-model misclassification (trust's flagship defense)
    'B1_threat_model_misclass,         # threat_model_foregrounding = required
    'B2_audience_sensitivity_collapse, # audience_feasibility in negotiation
    'B3_compliance_prior_drift,        # industry_standards in negotiation
    # Category C — unauthorized capability/scope expansion
    'C2_capability_collapse,           # intended gate prevents silent boundary changes
    'C3_helpfulness_inflation,         # trust-affecting changes need variance/amendment
    'C4_modernization_drift,           # dependency changes require an explicit project reason
    # Category D — epistemic failures
    'D4_error_hiding,                  # on_unmet = 'fail makes hiding impossible
    'D5_sycophancy,                    # pledge forces AI to hold line against enthusiasm
    'D6_false_pessimism,               # negotiation requires AI to cite constraint, not assert impossibility
    # Category E — refactor/churn
    'E4_cargo_cult_security,           # probes VERIFY the claimed protection actually runs
    # Category F — session drift
    'F1_across_session_forgetting,     # on_open reads last-ratification, drift log, recent ANCHORs
  ],
}
