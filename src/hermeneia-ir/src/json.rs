// SPDX-FileCopyrightText: © 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// SPDX-License-Identifier: MPL-2.0
//
// A minimal std-only JSON value, parser, and writer. Deliberately small: the
// workspace takes no crates.io dependencies (see the workspace Cargo.toml), and
// the Trope IR surface we read and write is narrow.

use std::collections::BTreeMap;
use std::fmt::Write as _;

#[derive(Clone, Debug, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(i64),
    Str(String),
    Arr(Vec<Json>),
    /// Insertion order is not preserved; the IR schema does not depend on it.
    Obj(BTreeMap<String, Json>),
}

impl Json {
    pub fn get(&self, k: &str) -> Option<&Json> {
        match self {
            Json::Obj(m) => m.get(k),
            _ => None,
        }
    }
    pub fn as_str(&self) -> Option<&str> {
        match self {
            Json::Str(s) => Some(s),
            _ => None,
        }
    }
    pub fn as_i64(&self) -> Option<i64> {
        match self {
            Json::Num(n) => Some(*n),
            _ => None,
        }
    }
    pub fn as_arr(&self) -> Option<&[Json]> {
        match self {
            Json::Arr(a) => Some(a),
            _ => None,
        }
    }
    pub fn obj(pairs: Vec<(&str, Json)>) -> Json {
        Json::Obj(pairs.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
    }
    pub fn str(s: impl Into<String>) -> Json {
        Json::Str(s.into())
    }
}

// ───────────────────────────── writer ─────────────────────────────

pub fn write(v: &Json) -> String {
    let mut out = String::new();
    write_into(v, 0, &mut out);
    out.push('\n');
    out
}

fn escape(s: &str, out: &mut String) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

fn write_into(v: &Json, depth: usize, out: &mut String) {
    let pad = |n: usize, out: &mut String| {
        for _ in 0..n {
            out.push_str("  ");
        }
    };
    match v {
        Json::Null => out.push_str("null"),
        Json::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Json::Num(n) => {
            let _ = write!(out, "{}", n);
        }
        Json::Str(s) => escape(s, out),
        Json::Arr(a) if a.is_empty() => out.push_str("[]"),
        Json::Arr(a) => {
            out.push_str("[\n");
            for (i, e) in a.iter().enumerate() {
                pad(depth + 1, out);
                write_into(e, depth + 1, out);
                if i + 1 < a.len() {
                    out.push(',');
                }
                out.push('\n');
            }
            pad(depth, out);
            out.push(']');
        }
        Json::Obj(m) if m.is_empty() => out.push_str("{}"),
        Json::Obj(m) => {
            out.push_str("{\n");
            for (i, (k, val)) in m.iter().enumerate() {
                pad(depth + 1, out);
                escape(k, out);
                out.push_str(": ");
                write_into(val, depth + 1, out);
                if i + 1 < m.len() {
                    out.push(',');
                }
                out.push('\n');
            }
            pad(depth, out);
            out.push('}');
        }
    }
}

// ───────────────────────────── parser ─────────────────────────────

pub fn parse(src: &str) -> Result<Json, String> {
    let mut p = P {
        s: src.as_bytes(),
        i: 0,
    };
    let v = p.value()?;
    p.ws();
    if p.i != p.s.len() {
        return Err(format!("trailing input at byte {}", p.i));
    }
    Ok(v)
}

struct P<'a> {
    s: &'a [u8],
    i: usize,
}

impl<'a> P<'a> {
    fn ws(&mut self) {
        while self.i < self.s.len() && matches!(self.s[self.i], b' ' | b'\n' | b'\t' | b'\r') {
            self.i += 1;
        }
    }
    fn value(&mut self) -> Result<Json, String> {
        self.ws();
        if self.i >= self.s.len() {
            return Err("unexpected end of input".into());
        }
        match self.s[self.i] {
            b'"' => self.string().map(Json::Str),
            b'{' => self.object(),
            b'[' => self.array(),
            b't' => self.lit("true").map(|_| Json::Bool(true)),
            b'f' => self.lit("false").map(|_| Json::Bool(false)),
            b'n' => self.lit("null").map(|_| Json::Null),
            c if c == b'-' || c.is_ascii_digit() => self.number(),
            c => Err(format!(
                "unexpected character '{}' at byte {}",
                c as char, self.i
            )),
        }
    }
    fn lit(&mut self, w: &str) -> Result<(), String> {
        if self.s[self.i..].starts_with(w.as_bytes()) {
            self.i += w.len();
            Ok(())
        } else {
            Err(format!("expected '{}' at byte {}", w, self.i))
        }
    }
    fn number(&mut self) -> Result<Json, String> {
        let start = self.i;
        if self.i < self.s.len() && self.s[self.i] == b'-' {
            self.i += 1;
        }
        while self.i < self.s.len() && self.s[self.i].is_ascii_digit() {
            self.i += 1;
        }
        // The IR uses integers only (delta is a Nat or the string "top").
        if self.i < self.s.len() && (self.s[self.i] == b'.' || self.s[self.i] | 32 == b'e') {
            return Err(format!("non-integer number at byte {}", start));
        }
        std::str::from_utf8(&self.s[start..self.i])
            .ok()
            .and_then(|t| t.parse::<i64>().ok())
            .map(Json::Num)
            .ok_or_else(|| format!("bad number at byte {}", start))
    }
    fn string(&mut self) -> Result<String, String> {
        self.i += 1; // opening quote
        let mut out = String::new();
        while self.i < self.s.len() {
            let c = self.s[self.i];
            self.i += 1;
            match c {
                b'"' => return Ok(out),
                b'\\' => {
                    if self.i >= self.s.len() {
                        break;
                    }
                    let e = self.s[self.i];
                    self.i += 1;
                    match e {
                        b'n' => out.push('\n'),
                        b't' => out.push('\t'),
                        b'r' => out.push('\r'),
                        b'b' => out.push('\u{8}'),
                        b'f' => out.push('\u{c}'),
                        b'u' => {
                            if self.i + 4 > self.s.len() {
                                return Err("truncated \\u escape".into());
                            }
                            let hex = std::str::from_utf8(&self.s[self.i..self.i + 4])
                                .map_err(|_| "bad \\u escape".to_string())?;
                            let cp = u32::from_str_radix(hex, 16)
                                .map_err(|_| "bad \\u escape".to_string())?;
                            out.push(char::from_u32(cp).unwrap_or('\u{fffd}'));
                            self.i += 4;
                        }
                        other => out.push(other as char),
                    }
                }
                _ => {
                    // Collect a full UTF-8 sequence.
                    let start = self.i - 1;
                    let len = utf8_len(c);
                    self.i = start + len;
                    if self.i > self.s.len() {
                        return Err("truncated UTF-8 sequence".into());
                    }
                    match std::str::from_utf8(&self.s[start..self.i]) {
                        Ok(t) => out.push_str(t),
                        Err(_) => return Err("invalid UTF-8 in string".into()),
                    }
                }
            }
        }
        Err("unterminated string".into())
    }
    fn array(&mut self) -> Result<Json, String> {
        self.i += 1; // [
        let mut a = Vec::new();
        loop {
            self.ws();
            if self.i >= self.s.len() {
                return Err("unterminated array".into());
            }
            if self.s[self.i] == b']' {
                self.i += 1;
                return Ok(Json::Arr(a));
            }
            a.push(self.value()?);
            self.ws();
            if self.i < self.s.len() && self.s[self.i] == b',' {
                self.i += 1;
            }
        }
    }
    fn object(&mut self) -> Result<Json, String> {
        self.i += 1; // {
        let mut m = BTreeMap::new();
        loop {
            self.ws();
            if self.i >= self.s.len() {
                return Err("unterminated object".into());
            }
            if self.s[self.i] == b'}' {
                self.i += 1;
                return Ok(Json::Obj(m));
            }
            self.ws();
            if self.s[self.i] != b'"' {
                return Err(format!("expected key string at byte {}", self.i));
            }
            let k = self.string()?;
            self.ws();
            if self.i >= self.s.len() || self.s[self.i] != b':' {
                return Err(format!("expected ':' at byte {}", self.i));
            }
            self.i += 1;
            let v = self.value()?;
            m.insert(k, v);
            self.ws();
            if self.i < self.s.len() && self.s[self.i] == b',' {
                self.i += 1;
            }
        }
    }
}

fn utf8_len(b: u8) -> usize {
    if b < 0x80 {
        1
    } else if b >> 5 == 0b110 {
        2
    } else if b >> 4 == 0b1110 {
        3
    } else {
        4
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_nested() {
        let src = r#"{"a":[1,2,{"b":"x"}],"c":true,"d":null}"#;
        let v = parse(src).expect("parse");
        let again = parse(&write(&v)).expect("reparse");
        assert_eq!(v, again);
    }

    #[test]
    fn escapes_survive() {
        let v = Json::str("quote \" backslash \\ newline \n");
        assert_eq!(parse(&write(&v)).unwrap(), v);
    }

    #[test]
    fn rejects_trailing_input() {
        assert!(parse("{} {}").is_err());
    }

    #[test]
    fn parses_utf8_strings() {
        let v = parse(r#""de Man — Romantic irony""#).unwrap();
        assert_eq!(v.as_str().unwrap(), "de Man — Romantic irony");
    }
}
