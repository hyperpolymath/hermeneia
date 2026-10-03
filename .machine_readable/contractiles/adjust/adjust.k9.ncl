K9!
# SPDX-License-Identifier: MPL-2.0
# adjust.k9.ncl — K9 trust-tier component of the adjust trident
# Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Pairs with: Adjustfile.a2ml (declaration) + adjust.ncl (runner).
#
# Verb:       adjust          (drift tolerances + corrective actions)
# Tier:       Yard            (read-only local measurement)
#                              No automatic mutation is authorized.
# Authority:  advisory        (continue-with-warnings; not blocking)
#
# Hermeneia-specific adjust scope: advisory review of plain-text CLI
# accessibility, actionable diagnostics, and truthful implementation-status
# claims. There is no graphical interface and no WCAG claim in this draft.
# Corrective actions are maintainer-reviewed recommendations; automatic file
# edits are disabled. The compatible contractile runner is not bundled.
#
# Cardinality: one adjust trident per repository. No numeric score is invented.

let base    = import "../_base.ncl" in

{
  pedigree = base.pedigree_schema & {
    name = "adjust.k9.ncl",
    component_type = "hermeneia-contractile",
    schema_version = "1.0.0",
    contractile_verb = "adjust",
    paired_xfile     = "../adjust/Adjustfile.a2ml",
    paired_runner    = "../adjust/adjust.ncl",

    tier      = 'Yard,
    authority = 'advisory,

    metadata = {
      name = "adjust-k9",
      version = "1.1.0",
      description = "Declares advisory Hermeneia text-CLI, diagnostic, and implementation-status tolerances. Corrective actions are recommendations; automatic writes are disabled.",
      paired_xfile = "Adjustfile.a2ml",
      paired_runner = "adjust.ncl",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },

    security = {
      leash = 'Yard,
      trust_level = "read-only tolerance measurement + human-reviewed recommendations",
      allow_network = false,
      allow_filesystem_write_conditional = false,
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
    # adjust-specific: which tolerance band the variance widens
    tolerance_band_widened | String,
    widened_to_value | String,
  },

  execution = {
    triggers = [ 'session_close, 'on_demand, 'pre_push ],

    per_tolerance = {
      measure_drift = true,
      record_outcome = true,
      respect_variance = true,
      # Advisory only: report the variance; any correction is reviewed by a
      # maintainer. Filesystem writes are disabled in this project profile.
      on_exceeded = 'warn,
      on_auto_fix_applied = 'record_and_continue,
      on_auto_fix_unavailable = 'record_as_advisory_drift,
      # Cumulative-drift detection (adjust's specialty)
      track_drift_trend_over_sessions = true,
      flag_accelerating_drift = true,
    },

    evidence_sinks = [
      { kind = 'verisimdb, table = "contractile_executions",
        schema = "contractile_execution_v1",
        aux_tables = [ "adjust_drift_history" ] },
      { kind = 'drift_log, path = ".machine_readable/descriptiles/DRIFT.a2ml",
        append_only = true },
    ],

    on_close = {
      re_measure_all_tolerances = true,
      diff_against_last_ratification = true,
      emit_drift_entries_for_tolerance_exceeded = true,
      surface_expired_variances = true,
      surface_accelerating_drift = true,
      # adjust is advisory — does NOT block session close.
      block_session_close_on_any_drift = false,
    },

    on_open = {
      render_summary = 'plain_language,
      include_drift_log_from_last_close = true,
      include_active_variances = true,
      include_recent_anchors = true,
      anchor_lookback_weeks = 8,
      include_tolerance_trend_summary = true,

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
            pledge = "I have reviewed the tolerance bands and corrective actions. I accept accountability for reviewing drift warnings rather than muting them, and for re-tuning tolerances via amendment when the intended operating envelope changes.",
            signature_required = true,
          },
          {
            role = 'ai_agent,
            pledge = "I will surface tolerance breaches and accelerating-drift patterns at session close; I will propose corrective actions rather than widening tolerances silently; I will require amendment for legitimate tolerance re-tuning, not quiet band-widening.",
            signature_required = true,
          },
        ],
        signed_record_destination = ".machine_readable/descriptiles/ratification-<session-id>.a2ml",
        must_precede_work = true,
      },

      ratification_record_shape = {
        includes_negotiation_transcript = true,
        includes_both_pledges = true,
        includes_tolerance_bands_snapshot = true,
        signed = true,
        dated = true,
        session_id = 'required,
        contract_hash = 'required,
      },
    },
  },

  failure_mode_defenses = [
    'A1_enthusiasm_capture,
    'C3_helpfulness_inflation,      # helpful additions surfaced if they widen tolerances silently
    'C4_modernization_drift,
    'E2_cosmetic_churn,             # adjust tracks cumulative churn
    'F2_context_window_erosion,     # parameter drift across sessions detected
  ],
}
