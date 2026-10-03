;; SPDX-License-Identifier: MPL-2.0
;; Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
;;
;; Guix development environment for Hermeneia.
;;
;;   guix shell -D -f build/guix.scm
;;
;; Guix is the sole package manager estate-wide and Nix is retired:
;; .github/workflows/guix-policy.yml hard-fails on any *.nix file in the tree,
;; so this file is the repo's only packaging artefact. Note the path — it is
;; build/guix.scm, not ./guix.scm, which is why .envrc used to probe for the
;; wrong file and silently provide no toolchain at all.
;;
;; ─── WHAT THIS IS, AND WHAT IT IS NOT ────────────────────────────────────────
;; This is a DEV-SHELL manifest, consumed as `guix shell -D -f ...`, where -D
;; pulls in the package's inputs (and native-inputs) as the shell's toolchain.
;; It is NOT a buildable package, and does not claim to be:
;;
;;   * (source #f) — there is no origin, so `guix build` has nothing to fetch.
;;   * gnu-build-system with no #:phases — there is no configure/make/install to
;;     run even if there were a source.
;;
;; Making this a real package (a cargo-build-system origin over the workspace,
;; with the five member crates) is still owed; STATE.a2ml records it as the
;; second half of "retire the flake AND make the Guix side real in the same
;; change". The flake half is done — there is no flake.nix and none is permitted
;; at the root (.machine_readable/root-allow.txt).
;;
;; ─── INPUTS: matched to what this repository actually builds with ────────────
;; .machine_readable/descriptiles/anchors/ANCHOR.a2ml [implementation-policy]
;; declares:
;;     allowed   = Rust, Idris2, Zig, Scheme, Shell, Just, AsciiDoc, Markdown
;;     forbidden = Node.js, npm
;;
;; The inputs this file inherited from the template listed openjdk, go, node and
;; python. None of the four appears anywhere in this repository — the working
;; implementation is a Rust workspace (src/hermeneia-{syntax,ir,store,core,cli}),
;; the ABI seam is Idris2 (src/interface/Abi/) and the FFI is Zig
;; (src/interface/ffi/) — and shipping node as a dev-shell input while ANCHOR
;; forbids Node.js is a contradiction a machine can read. All four are removed,
;; with their modules.
;;
;; cmake stays: zig's build wants a C toolchain present. make and coreutils stay
;; for the shell scripts under scripts/, tests/ and session/.
;;
;; NOT YET ADDED, deliberately: idris2 and just. Both are in ANCHOR's allowed
;; list and both are needed (idris2 --typecheck abi.ipkg is the ABI gate; just is
;; the task runner), so the shell is incomplete without them. They are absent
;; because the Guix module and variable names could not be verified from this
;; checkout, and a wrong (use-modules ...) form makes the whole shell fail to
;; open — a worse outcome than a shell that opens and is missing two tools.
;; Verify against a real Guix and add:
;;     (gnu packages idris)        -> idris2
;;     (gnu packages rust-apps)    -> just
;; Until then, mise.toml is the route that provides both.

(use-modules (guix packages)
             (guix build-system gnu)
             (guix licenses)
             (gnu packages base)
             (gnu packages bash)
             (gnu packages cmake)
             (gnu packages rust)
             (gnu packages zig))

(package
  (name "hermeneia")
  (version "0.1.0")
  (source #f)
  (build-system gnu-build-system)
  (inputs (list coreutils bash make rust cmake zig))
  (synopsis "Voking / imminence query language for Vocarium")
  (description
   "Hermeneia is an experimental query language for trope-aware, loss-aware,
warrant-aware stores.  It calls particulars stored in Vocarium into a declared
use-relation — invoke, evoke, convoke, transvoke, provoke, intervoke, revoke —
and reports what is preserved, lost, licensed, or insufficient under a use-model,
separating the retrieved from the interpretable from the licensed.  Part of the
hyperpolymath voking stack: Vocarium stores, Haec transforms, Hermeneia queries.")
  (home-page "https://github.com/hyperpolymath/hermeneia")
  (license ((@@ (guix licenses) license) "MPL-2.0" "https://github.com/hyperpolymath/palimpsest-license")))
