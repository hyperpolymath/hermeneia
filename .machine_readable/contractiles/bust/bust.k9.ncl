K9!
# SPDX-License-Identifier: MPL-2.0
# bust.k9.ncl — K9 trust-tier component of the bust trident
# Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Pairs with: Bustfile.a2ml (declaration) + bust.ncl (runner).
#
# Verb:       bust            (Hermeneia fail-closed stop conditions)
# Tier:       Hunt            (repository-local synthetic regression tests)
# Authority:  blocking        (intended gate for declared stop conditions)
#
# Hermeneia-specific stops include recognized-but-unimplemented vokes,
# malformed/deceptive JSONL, a missing tropecheck executable, and requests for
# unsupported loss/warrant output. The tests use synthetic fixtures; they do
# not target external systems or user data. This repository has no expiry-
# bearing runtime credential, so no certificate/token/grant expiry is claimed.
#
# Cardinality: one bust trident per repository. The compatible runner is not
# bundled, so these K9 execution hooks are a policy target, not active CI.

let base    = import "../_base.ncl" in

{
  pedigree = base.pedigree_schema & {
    name = "bust.k9.ncl",
    component_type = "hermeneia-contractile",
    schema_version = "1.0.0",
    contractile_verb = "bust",
    paired_xfile     = "../bust/Bustfile.a2ml",
    paired_runner    = "../bust/bust.ncl",

    tier      = 'Hunt,
    authority = 'blocking,

    metadata = {
      name = "bust-k9",
      version = "1.1.0",
      description = "Declares fail-closed stops for Hermeneia parser/store/oracle boundaries. Intended blocking policy; no runtime expiry credential or bundled contractile CLI.",
      paired_xfile = "Bustfile.a2ml",
      paired_runner = "bust.ncl",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },

    security = {
      leash = 'Hunt,
      signature_required = true,
      trust_level = "repository-local synthetic regression checks with subprocess",
      allow_network = false,
      allow_filesystem_write = false,
      allow_subprocess = true,
      probe_scope = 'read_only,
    },
  },

  variance_schema = {
    entry_id     | String,
    reason       | String,
    approved_by  | String,
    scope        | String,
    expires      | String,
    review_notes | String | optional,
    severity_acknowledged | [| 'critical, 'high, 'medium |],
    waived_consequence_description | String,
  },

  execution = {
    triggers = [ 'session_close, 'on_demand, 'pre_push, 'pre_merge ],

    per_hard_stop = {
      run_probe = true,
      record_outcome = true,
      respect_variance = true,
      on_triggered = 'fail,        # BLOCKING — bust condition hit = block
      severity_escalation = 'honour,
      # bust-specific: recognized but unimplemented operations remain hard stops
      flag_unimplemented_operation_as_stop = true,
    },

    evidence_sinks = [
      { kind = 'verisimdb, table = "contractile_executions",
        schema = "contractile_execution_v1",
        aux_tables = [ "bust_triggers_history" ] },
      { kind = 'drift_log, path = ".machine_readable/descriptiles/DRIFT.a2ml",
        append_only = true },
    ],

    on_close = {
      re_execute_all_hard_stops = true,
      diff_against_last_ratification = true,
      emit_drift_entries_for_new_triggers = true,
      surface_expired_variances = true,
      block_session_close_on_critical_bust = true,
    },

    on_open = {
      render_summary = 'plain_language,
      include_drift_log_from_last_close = true,
      include_active_variances = true,
      include_recent_anchors = true,
      anchor_lookback_weeks = 8,
      include_silent_regressions = true,

      negotiation = {
        required = true,
        ai_required_inputs = [
          'timeline_realism,
          'industry_standards,
          'audience_feasibility,
          'resulting_invariants,
          'ecosystem_dependencies,
        ],
        user_engagement_required = true,
        user_engagement_mode = 'per_input_response,
        specification_translation = {
          ai_produces_spec_form = true,
          user_reviews_in_domain_language = true,
          schema_authoring_is_ai_responsibility = true,
          translation_faithfulness_auditable = true,
        },
      },

      accountability_pledge = {
        required = true,
        parties = [
          {
            role = 'user,
            pledge = "I have reviewed the proposed stop conditions for unsupported vokes, malformed/deceptive local data, unavailable tropecheck, and unsupported loss/warrant output. I understand that these are a draft until ratified and that no expiry-bearing runtime credential is currently asserted.",
            signature_required = true,
          },
          {
            role = 'ai_agent,
            pledge = "I will refuse to convert unsupported operations, malformed/deceptive data, missing checker output, or unavailable evidence into a successful verdict. I will keep probes synthetic and repository-local, and require maintainer review before adding a new stop condition or destructive failure drill.",
            signature_required = true,
          },
        ],
        signed_record_destination = ".machine_readable/descriptiles/ratification-<session-id>.a2ml",
        must_precede_work = true,
      },

      ratification_record_shape = {
        includes_negotiation_transcript = true,
        includes_both_pledges = true,
        signed = true,
        dated = true,
        session_id = 'required,
        contract_hash = 'required,
      },
    },
  },

  failure_mode_defenses = [
    'A1_enthusiasm_capture,
    'C2_capability_collapse,       # unsupported operations remain explicitly unsupported
    'C4_modernization_drift,       # new behavior needs tests and an explicit contract
    'D4_error_hiding,
    'E1_refactor_stampede,         # refactor must retain the stop-condition regression tests
    'F1_across_session_forgetting, # bust triggers persist across sessions
  ],
}
