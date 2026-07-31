// SPDX-FileCopyrightText: © 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// SPDX-License-Identifier: MPL-2.0
//
// The .hil surface syntax.
//
// Slice v1 implements `invoke` only. The remaining six voking operations parse
// to a recognised-but-unimplemented error rather than a syntax error, so that
// the diagnostic tells the truth about which of the two it is.

use std::fmt;

// ───────────────────────────── AST ─────────────────────────────

/// The seven voking operations. Only `Invoke` carries a body in slice v1.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Voke {
    Invoke,
    Evoke,
    Convoke,
    Transvoke,
    Provoke,
    Intervoke,
    Revoke,
}

impl Voke {
    pub fn from_keyword(k: &str) -> Option<Voke> {
        Some(match k {
            "invoke" => Voke::Invoke,
            "evoke" => Voke::Evoke,
            "convoke" => Voke::Convoke,
            "transvoke" => Voke::Transvoke,
            "provoke" => Voke::Provoke,
            "intervoke" => Voke::Intervoke,
            "revoke" => Voke::Revoke,
            _ => return None,
        })
    }
    pub fn as_str(self) -> &'static str {
        match self {
            Voke::Invoke => "invoke",
            Voke::Evoke => "evoke",
            Voke::Convoke => "convoke",
            Voke::Transvoke => "transvoke",
            Voke::Provoke => "provoke",
            Voke::Intervoke => "intervoke",
            Voke::Revoke => "revoke",
        }
    }
    /// Whether a p-sufficiency verdict is required. Only three of seven are.
    /// See docs/SPEC.adoc §"The division of labour".
    pub fn needs_verdict(self) -> bool {
        matches!(self, Voke::Invoke | Voke::Provoke | Voke::Intervoke)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Show {
    Verdict,
    Loss,
    Warrant,
    FailurePoints,
}

impl Show {
    fn from_word(w: &str) -> Option<Show> {
        Some(match w {
            "verdict" => Show::Verdict,
            "loss" => Show::Loss,
            "warrant" => Show::Warrant,
            "failure_points" => Show::FailurePoints,
            _ => return None,
        })
    }
    pub fn as_str(self) -> &'static str {
        match self {
            Show::Verdict => "verdict",
            Show::Loss => "loss",
            Show::Warrant => "warrant",
            Show::FailurePoints => "failure_points",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Invoke {
    pub subject: String,
    pub use_model: String,
    pub show: Vec<Show>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Query {
    Invoke(Invoke),
}

// ───────────────────────────── errors ─────────────────────────────

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ParseError {
    /// A genuine syntax error.
    Syntax { line: usize, msg: String },
    /// A real voking operation that slice v1 does not yet implement. This is
    /// deliberately distinct from a syntax error.
    Unimplemented(Voke),
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ParseError::Syntax { line, msg } => write!(f, "line {}: {}", line, msg),
            ParseError::Unimplemented(v) => write!(
                f,
                "`{}` is a recognised voking operation but is not implemented in this build \
                 (slice v1 implements `invoke`)",
                v.as_str()
            ),
        }
    }
}

impl std::error::Error for ParseError {}

// ───────────────────────────── lexer ─────────────────────────────

#[derive(Clone, Debug, PartialEq, Eq)]
enum Tok {
    Word(String),
    Str(String),
    Comma,
}

struct Lexed {
    toks: Vec<(Tok, usize)>,
}

fn lex(src: &str) -> Result<Lexed, ParseError> {
    let mut toks = Vec::new();
    for (lineno, raw) in src.lines().enumerate() {
        let line = lineno + 1;
        // `#` begins a comment, except inside a string.
        let mut chars = raw.chars().peekable();
        while let Some(&c) = chars.peek() {
            if c.is_whitespace() {
                chars.next();
            } else if c == '#' {
                break;
            } else if c == ',' {
                chars.next();
                toks.push((Tok::Comma, line));
            } else if c == '"' {
                chars.next();
                let mut s = String::new();
                let mut closed = false;
                while let Some(ch) = chars.next() {
                    if ch == '\\' {
                        match chars.next() {
                            Some('n') => s.push('\n'),
                            Some('t') => s.push('\t'),
                            Some(other) => s.push(other),
                            None => break,
                        }
                    } else if ch == '"' {
                        closed = true;
                        break;
                    } else {
                        s.push(ch);
                    }
                }
                if !closed {
                    return Err(ParseError::Syntax {
                        line,
                        msg: "unterminated string literal".into(),
                    });
                }
                toks.push((Tok::Str(s), line));
            } else {
                let mut w = String::new();
                while let Some(&ch) = chars.peek() {
                    if ch.is_whitespace() || ch == ',' || ch == '"' || ch == '#' {
                        break;
                    }
                    w.push(ch);
                    chars.next();
                }
                toks.push((Tok::Word(w), line));
            }
        }
    }
    Ok(Lexed { toks })
}

// ───────────────────────────── parser ─────────────────────────────

struct P {
    toks: Vec<(Tok, usize)>,
    i: usize,
}

impl P {
    fn line(&self) -> usize {
        self.toks
            .get(self.i)
            .or_else(|| self.toks.last())
            .map(|(_, l)| *l)
            .unwrap_or(1)
    }
    fn err<T>(&self, msg: impl Into<String>) -> Result<T, ParseError> {
        Err(ParseError::Syntax {
            line: self.line(),
            msg: msg.into(),
        })
    }
    fn peek_word(&self) -> Option<&str> {
        match self.toks.get(self.i) {
            Some((Tok::Word(w), _)) => Some(w.as_str()),
            _ => None,
        }
    }
    fn eat_word(&mut self, want: &str) -> Result<(), ParseError> {
        match self.toks.get(self.i) {
            Some((Tok::Word(w), _)) if w == want => {
                self.i += 1;
                Ok(())
            }
            Some((t, _)) => self.err(format!("expected `{}`, found {}", want, describe(t))),
            None => self.err(format!("expected `{}`, found end of input", want)),
        }
    }
    fn eat_string(&mut self, what: &str) -> Result<String, ParseError> {
        match self.toks.get(self.i) {
            Some((Tok::Str(s), _)) => {
                let s = s.clone();
                self.i += 1;
                Ok(s)
            }
            Some((t, _)) => self.err(format!("expected a quoted {}, found {}", what, describe(t))),
            None => self.err(format!("expected a quoted {}, found end of input", what)),
        }
    }
}

fn describe(t: &Tok) -> String {
    match t {
        Tok::Word(w) => format!("`{}`", w),
        Tok::Str(s) => format!("string \"{}\"", s),
        Tok::Comma => "`,`".to_string(),
    }
}

/// Parse a `.hil` source into a query.
///
/// Grammar (slice v1):
/// ```text
/// query   := "invoke" STRING "under" "use_model" STRING "show" showlist
/// showlist:= SHOW ("," SHOW)*
/// SHOW    := "verdict" | "loss" | "warrant" | "failure_points"
/// ```
/// `#` begins a line comment.
pub fn parse(src: &str) -> Result<Query, ParseError> {
    let lexed = lex(src)?;
    let mut p = P {
        toks: lexed.toks,
        i: 0,
    };

    let head = match p.peek_word() {
        Some(w) => w.to_string(),
        None => return p.err("empty query"),
    };
    let voke = match Voke::from_keyword(&head) {
        Some(v) => v,
        None => {
            return p.err(format!(
                "`{}` is not a voking operation (expected one of: invoke, evoke, convoke, \
                 transvoke, provoke, intervoke, revoke)",
                head
            ))
        }
    };
    if voke != Voke::Invoke {
        return Err(ParseError::Unimplemented(voke));
    }
    p.i += 1;

    let subject = p.eat_string("subject")?;
    p.eat_word("under")?;
    p.eat_word("use_model")?;
    let use_model = p.eat_string("use-model name")?;
    p.eat_word("show")?;

    let mut show = Vec::new();
    loop {
        match p.toks.get(p.i) {
            Some((Tok::Word(w), _)) => {
                match Show::from_word(w) {
                    Some(s) => show.push(s),
                    None => {
                        return p.err(format!(
                        "`{}` is not showable (expected: verdict, loss, warrant, failure_points)",
                        w
                    ))
                    }
                }
                p.i += 1;
            }
            Some((t, _)) => {
                return p.err(format!("expected a field to show, found {}", describe(t)))
            }
            None => return p.err("expected a field to show, found end of input"),
        }
        match p.toks.get(p.i) {
            Some((Tok::Comma, _)) => {
                p.i += 1;
            }
            _ => break,
        }
    }

    if p.i != p.toks.len() {
        let t = &p.toks[p.i].0;
        return p.err(format!("unexpected trailing {}", describe(t)));
    }
    if show.is_empty() {
        return p.err("`show` requires at least one field");
    }

    Ok(Query::Invoke(Invoke {
        subject,
        use_model,
        show,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    const README_EXAMPLE: &str = r#"
invoke "authentic language"
under use_model "critical-paraphrase"
show verdict
"#;

    #[test]
    fn parses_the_readme_example() {
        let q = parse(README_EXAMPLE).expect("should parse");
        let Query::Invoke(i) = q;
        assert_eq!(i.subject, "authentic language");
        assert_eq!(i.use_model, "critical-paraphrase");
        assert_eq!(i.show, vec![Show::Verdict]);
    }

    #[test]
    fn parses_a_show_list() {
        let q = parse("invoke \"x\" under use_model \"u\" show verdict, loss, warrant").unwrap();
        let Query::Invoke(i) = q;
        assert_eq!(i.show, vec![Show::Verdict, Show::Loss, Show::Warrant]);
    }

    #[test]
    fn ignores_comments_and_blank_lines() {
        let src = "# a comment\n\ninvoke \"x\"  # trailing\nunder use_model \"u\"\nshow verdict\n";
        assert!(parse(src).is_ok());
    }

    #[test]
    fn hash_inside_a_string_is_not_a_comment() {
        let q = parse("invoke \"a # b\" under use_model \"u\" show verdict").unwrap();
        let Query::Invoke(i) = q;
        assert_eq!(i.subject, "a # b");
    }

    #[test]
    fn other_vokes_are_unimplemented_not_syntax_errors() {
        for kw in [
            "evoke",
            "convoke",
            "transvoke",
            "provoke",
            "intervoke",
            "revoke",
        ] {
            match parse(&format!("{} \"x\"", kw)) {
                Err(ParseError::Unimplemented(v)) => assert_eq!(v.as_str(), kw),
                other => panic!("{kw}: expected Unimplemented, got {:?}", other),
            }
        }
    }

    #[test]
    fn unknown_head_is_a_syntax_error() {
        assert!(matches!(
            parse("select * from tropes"),
            Err(ParseError::Syntax { .. })
        ));
    }

    #[test]
    fn reports_the_offending_line() {
        let err = parse("invoke \"x\"\nunder use_model \"u\"\nshow bogus").unwrap_err();
        match err {
            ParseError::Syntax { line, ref msg } => {
                assert_eq!(line, 3);
                assert!(msg.contains("bogus"));
            }
            other => panic!("expected syntax error, got {:?}", other),
        }
    }

    #[test]
    fn unterminated_string_is_caught() {
        assert!(matches!(
            parse("invoke \"x"),
            Err(ParseError::Syntax { .. })
        ));
    }

    #[test]
    fn only_three_operations_need_a_verdict() {
        let need: Vec<_> = [
            Voke::Invoke,
            Voke::Evoke,
            Voke::Convoke,
            Voke::Transvoke,
            Voke::Provoke,
            Voke::Intervoke,
            Voke::Revoke,
        ]
        .into_iter()
        .filter(|v| v.needs_verdict())
        .collect();
        assert_eq!(need, vec![Voke::Invoke, Voke::Provoke, Voke::Intervoke]);
    }
}
