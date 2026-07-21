// SPDX-FileCopyrightText: © 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// SPDX-License-Identifier: MPL-2.0
//
// End-to-end tests for the vertical slice: .hil source -> plan -> Trope IR ->
// tropecheck -> verdict.
//
// These tests REQUIRE a real checker. Per the repository's fail-closed and
// no-silent-skip constraints (.machine_readable AGENTIC), a missing checker is
// a loud failure with instructions, never an `#[ignore]` that reports green
// while proving nothing.
//
//   cargo build --release --manifest-path <trope-checker>/src/rust/Cargo.toml
//   HERMENEIA_TROPECHECK=<...>/tropecheck-rs cargo test

use std::path::PathBuf;
use std::process::Command;

fn checker() -> PathBuf {
    match std::env::var_os("HERMENEIA_TROPECHECK") {
        Some(p) => {
            let p = PathBuf::from(p);
            assert!(
                p.is_file(),
                "HERMENEIA_TROPECHECK points at {}, which is not a file",
                p.display()
            );
            p
        }
        None => panic!(
            "HERMENEIA_TROPECHECK is not set, so the end-to-end slice cannot be verified.\n\
             Build a checker and point at it:\n  \
             cargo build --release --manifest-path <trope-checker>/src/rust/Cargo.toml\n  \
             export HERMENEIA_TROPECHECK=<trope-checker>/src/rust/target/release/tropecheck-rs\n\
             This test fails rather than skipping: a green run must mean the slice was checked."
        ),
    }
}

fn hermeneia() -> PathBuf {
    // The integration test binary lives in target/<profile>/deps/; the CLI is
    // two levels up.
    let mut p = std::env::current_exe().expect("test exe path");
    p.pop();
    if p.ends_with("deps") {
        p.pop();
    }
    p.join("hermeneia")
}

struct Run {
    code: i32,
    stdout: String,
    stderr: String,
}

fn run(args: &[&str]) -> Run {
    let out = Command::new(hermeneia())
        .args(args)
        .output()
        .unwrap_or_else(|e| panic!("running {}: {}", hermeneia().display(), e));
    Run {
        code: out.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
    }
}

fn query(use_model: &str) -> Run {
    let tc = checker();
    let src = format!(
        "invoke \"authentic language\" under use_model \"{}\" show verdict",
        use_model
    );
    run(&["query", "--checker", tc.to_str().unwrap(), "-e", &src])
}

#[test]
fn readme_example_is_p_insufficient_with_the_expected_witness() {
    let r = query("critical-paraphrase");
    assert_eq!(
        r.code, 1,
        "expected p-insufficient exit 1\n{}{}",
        r.stdout, r.stderr
    );
    assert!(
        r.stdout.contains("verdict:   p-insufficient"),
        "{}",
        r.stdout
    );
    assert!(r.stdout.contains("e_paraphrase"), "{}", r.stdout);
    assert!(r.stdout.contains("fate.quality"), "{}", r.stdout);
}

/// The whole point of the language: the SAME particular, along the SAME path,
/// with the SAME declared grade, is licensed under one use and not another.
#[test]
fn the_same_particular_is_licensed_under_a_permissive_use() {
    let strict = query("critical-paraphrase");
    let loose = query("loose-gloss");
    assert_eq!(strict.code, 1, "strict use must be insufficient");
    assert_eq!(
        loose.code, 0,
        "permissive use must be sufficient\n{}{}",
        loose.stdout, loose.stderr
    );
    assert!(
        loose.stdout.contains("verdict:   p-sufficient"),
        "{}",
        loose.stdout
    );
}

/// The checker returning a VERDICT rather than exit 2 (validation-fault) is the
/// schema validation: `Checker.Decode` is the reference validator for Trope IR.
#[test]
fn emitted_ir_is_accepted_by_the_reference_validator() {
    for um in ["critical-paraphrase", "loose-gloss"] {
        let r = query(um);
        assert_ne!(
            r.code, 2,
            "{}: IR was rejected as malformed\n{}",
            um, r.stderr
        );
        assert_ne!(r.code, 3, "{}: io/checker error\n{}", um, r.stderr);
    }
}

#[test]
fn emit_ir_produces_the_required_top_level_keys() {
    let r = run(&[
        "query",
        "--emit-ir",
        "-e",
        "invoke \"authentic language\" under use_model \"critical-paraphrase\" show verdict",
    ]);
    assert_eq!(r.code, 0, "{}", r.stderr);
    for k in [
        "\"version\"",
        "\"profile\"",
        "\"nodes\"",
        "\"edges\"",
        "\"use_model\"",
    ] {
        assert!(
            r.stdout.contains(k),
            "emitted IR missing {}:\n{}",
            k,
            r.stdout
        );
    }
    assert!(r.stdout.contains("\"0.2\""));
    assert!(r.stdout.contains("\"prevent\""));
}

#[test]
fn show_loss_is_refused_rather_than_fabricated() {
    let tc = checker();
    let r = run(&[
        "query",
        "--checker",
        tc.to_str().unwrap(),
        "-e",
        "invoke \"authentic language\" under use_model \"critical-paraphrase\" show loss",
    ]);
    assert_eq!(r.code, 2, "expected a hermeneia-side refusal");
    assert!(r.stderr.contains("cannot show `loss`"), "{}", r.stderr);
}

#[test]
fn unimplemented_vokes_are_distinguished_from_syntax_errors() {
    let r = run(&["query", "-e", "evoke around \"authentic language\""]);
    assert_eq!(r.code, 2);
    assert!(r.stderr.contains("not implemented"), "{}", r.stderr);

    let s = run(&["query", "-e", "select * from tropes"]);
    assert_eq!(s.code, 2);
    assert!(s.stderr.contains("not a voking operation"), "{}", s.stderr);
}

#[test]
fn missing_checker_exits_three_with_instructions() {
    let r = Command::new(hermeneia())
        .args([
            "query",
            "-e",
            "invoke \"authentic language\" under use_model \"loose-gloss\" show verdict",
        ])
        .env_remove("HERMENEIA_TROPECHECK")
        .env("PATH", "/nonexistent")
        .output()
        .expect("spawn");
    assert_eq!(r.status.code(), Some(3));
    assert!(String::from_utf8_lossy(&r.stderr).contains("no tropecheck executable found"));
}
