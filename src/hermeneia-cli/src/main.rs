// SPDX-FileCopyrightText: © 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// SPDX-License-Identifier: MPL-2.0
//
// The hermeneia CLI. Parses a .hil query, plans it against a store, emits
// Trope IR v0.2, hands it to `tropecheck`, and renders the verdict.
//
// Exit codes deliberately mirror the checker's, so that a caller can treat
// hermeneia and tropecheck alike:
//   0  p-sufficient          2  a hermeneia-side fault (parse/plan/IR)
//   1  p-insufficient        3  io / checker-not-found        64  usage

use hermeneia_core::{plan, Plan};
use hermeneia_store::JsonlStore;
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::process::{exit, Command};

const USAGE: &str = "\
usage: hermeneia query [options] (<file.hil> | -e <source>)

options:
  -e <source>        read the query from the argument instead of a file
  --store <path>     JSONL store (default: the built-in seed corpus)
  --checker <path>   tropecheck executable
                     (default: $HERMENEIA_TROPECHECK, else `tropecheck` or
                      `tropecheck-rs` on PATH)
  --emit-ir          print the emitted Trope IR and exit without checking
";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() || args[0] == "-h" || args[0] == "--help" {
        print!("{}", USAGE);
        exit(if args.is_empty() { 64 } else { 0 });
    }
    if args[0] != "query" {
        die(
            64,
            &format!("unknown subcommand `{}`\n\n{}", args[0], USAGE),
        );
    }

    let mut source: Option<String> = None;
    let mut file: Option<PathBuf> = None;
    let mut store_path: Option<PathBuf> = None;
    let mut checker: Option<PathBuf> = None;
    let mut emit_ir = false;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-e" => {
                i += 1;
                source = Some(
                    args.get(i)
                        .cloned()
                        .unwrap_or_else(|| die(64, "-e needs a source")),
                );
            }
            "--store" => {
                i += 1;
                store_path = Some(PathBuf::from(
                    args.get(i)
                        .cloned()
                        .unwrap_or_else(|| die(64, "--store needs a path")),
                ));
            }
            "--checker" => {
                i += 1;
                checker = Some(PathBuf::from(
                    args.get(i)
                        .cloned()
                        .unwrap_or_else(|| die(64, "--checker needs a path")),
                ));
            }
            "--emit-ir" => emit_ir = true,
            other if other.starts_with('-') => die(64, &format!("unknown option `{}`", other)),
            other => file = Some(PathBuf::from(other)),
        }
        i += 1;
    }

    let src = match (source, file) {
        (Some(s), None) => s,
        (None, Some(f)) => std::fs::read_to_string(&f)
            .unwrap_or_else(|e| die(3, &format!("{}: {}", f.display(), e))),
        (Some(_), Some(_)) => die(64, "give either -e or a file, not both"),
        (None, None) => die(64, &format!("no query given\n\n{}", USAGE)),
    };

    let query = hermeneia_syntax::parse(&src).unwrap_or_else(|e| die(2, &format!("{}", e)));

    let store = match &store_path {
        Some(p) => JsonlStore::load_file(p).unwrap_or_else(|e| die(2, &format!("{}", e))),
        None => JsonlStore::seed(),
    };

    let planned: Plan = plan(&store, &query).unwrap_or_else(|e| die(2, &format!("{}", e)));
    let ir = planned.document.emit();

    if emit_ir {
        print!("{}", ir);
        exit(0);
    }

    let checker = checker
        .or_else(|| std::env::var_os("HERMENEIA_TROPECHECK").map(PathBuf::from))
        .or_else(|| which("tropecheck"))
        .or_else(|| which("tropecheck-rs"))
        .unwrap_or_else(|| {
            die(
                3,
                "no tropecheck executable found. Set HERMENEIA_TROPECHECK, pass --checker, \
                 or put `tropecheck` on PATH. Build one from trope-checker/src/rust with \
                 `cargo build --release`.",
            )
        });

    // The checker takes a path, not stdin, so the IR goes to a temporary file.
    let tmp = std::env::temp_dir().join(format!("hermeneia-{}.ir.json", std::process::id()));
    std::fs::write(&tmp, ir.as_bytes())
        .unwrap_or_else(|e| die(3, &format!("{}: {}", tmp.display(), e)));

    let out = Command::new(&checker).arg(&tmp).output();
    let _ = std::fs::remove_file(&tmp);
    let out = out.unwrap_or_else(|e| die(3, &format!("{}: {}", checker.display(), e)));

    let stdout = String::from_utf8_lossy(&out.stdout);
    let code = out.status.code().unwrap_or(3);
    render(&planned, stdout.trim(), code);
    exit(code);
}

/// Render the checker's terse output as a hermeneia result.
///
/// The checker prints `p-insufficient\twitness=<edge>\tcoord=<coord>`. It does
/// NOT print the per-dimension loss vector, so neither do we — the planner
/// already refused `show loss` rather than inventing one.
fn render(p: &Plan, out: &str, code: i32) {
    let mut fields = out.split('\t');
    let head = fields.next().unwrap_or("");
    let mut witness = None;
    let mut coord = None;
    for f in fields {
        if let Some(v) = f.strip_prefix("witness=") {
            witness = Some(v.to_string());
        } else if let Some(v) = f.strip_prefix("coord=") {
            coord = Some(v.to_string());
        }
    }

    if code >= 2 {
        eprintln!("checker fault: {}", out);
        return;
    }

    println!("subject:   \"{}\"", p.subject);
    println!("use_model: \"{}\"", p.use_model);
    println!("verdict:   {}", head);
    match (witness, coord) {
        (Some(w), Some(c)) => {
            println!("witness:   {} ({})", w, c);
            let effect = p
                .document
                .edges
                .iter()
                .find(|e| e.id == w)
                .map(|e| e.effect.as_str())
                .unwrap_or("?");
            println!(
                "           the `{}` step is where the floor was breached",
                effect
            );
        }
        _ => {
            if head == "p-insufficient" {
                println!("witness:   (none reported)");
            }
        }
    }
}

fn which(prog: &str) -> Option<PathBuf> {
    let path = std::env::var_os("PATH")?;
    std::env::split_paths(&path)
        .map(|d| d.join(prog))
        .find(|p| is_executable(p))
}

fn is_executable(p: &Path) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::metadata(p)
            .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    }
    #[cfg(not(unix))]
    {
        p.is_file()
    }
}

fn die(code: i32, msg: &str) -> ! {
    let _ = writeln!(std::io::stderr(), "hermeneia: {}", msg);
    exit(code)
}
