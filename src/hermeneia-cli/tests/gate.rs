// SPDX-FileCopyrightText: © 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// SPDX-License-Identifier: MPL-2.0
//
// The end-to-end slice (tests/slice.rs) is gated behind the `e2e` feature,
// because it needs a real `tropecheck` binary that a bare `cargo test` cannot
// assume is present.
//
// Gating is only honest if something still fails when the gate stops being
// opened. These tests run on EVERY `cargo test` and assert that the workflow
// which supplies the checker and enables the feature still exists and still
// does both. Delete or defeat that workflow and this goes red, rather than the
// slice quietly ceasing to be verified while CI reports green.

use std::path::PathBuf;

fn repo_root() -> PathBuf {
    // CARGO_MANIFEST_DIR is <root>/src/hermeneia-cli
    let mut p = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    p.pop();
    p.pop();
    p
}

fn workflow() -> String {
    let p = repo_root().join(".github/workflows/slice.yml");
    std::fs::read_to_string(&p).unwrap_or_else(|e| {
        panic!(
            "the end-to-end slice is gated behind the `e2e` feature, and the workflow that \
             opens that gate is missing: {} ({}).\nEither restore it or remove the gate — \
             the slice must not become unverified while CI stays green.",
            p.display(),
            e
        )
    })
}

#[test]
fn the_slice_workflow_exists() {
    assert!(!workflow().is_empty(), "slice.yml is empty");
}

#[test]
fn the_slice_workflow_enables_the_e2e_feature() {
    let w = workflow();
    assert!(
        w.contains("--features e2e"),
        "slice.yml no longer enables the `e2e` feature, so tests/slice.rs never runs. \
         CI would report green having checked nothing end to end."
    );
}

#[test]
fn the_slice_workflow_supplies_a_checker() {
    let w = workflow();
    assert!(
        w.contains("HERMENEIA_TROPECHECK"),
        "slice.yml no longer sets HERMENEIA_TROPECHECK, so the end-to-end tests would fail \
         for want of an oracle rather than run"
    );
    assert!(
        w.contains("trope-checker"),
        "slice.yml no longer builds trope-checker, so there is no oracle to check against"
    );
}

/// The seed corpus is the README's worked example. If they drift apart, the
/// documentation stops being the test.
#[test]
fn the_seed_corpus_matches_the_readme_example() {
    let readme = std::fs::read_to_string(repo_root().join("README.adoc")).expect("README.adoc");
    let corpus = hermeneia_store::SEED;
    for token in ["authentic language", "critical-paraphrase"] {
        assert!(
            readme.contains(token),
            "README.adoc no longer mentions \"{}\"",
            token
        );
        assert!(
            corpus.contains(token),
            "the seed corpus no longer contains \"{}\"; the docs and the tests have drifted",
            token
        );
    }
}
