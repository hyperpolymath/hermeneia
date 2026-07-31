// SPDX-FileCopyrightText: © 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// SPDX-License-Identifier: MPL-2.0
//
// The store seam.
//
// Vocarium does not exist yet. Hermeneia therefore ships its own JSONL store
// behind a narrow trait so that Vocarium can be substituted without the planner
// changing. See docs/SPEC.adoc §"The store seam".
//
// Note which side of the seam the grade algebra falls on: `neighbours` takes a
// bound in the retention order, so any implementation that supports it owns the
// cost of comparing grades. The planner never does. That is what keeps the
// algebra decision deferrable.

use hermeneia_ir::json::{self, Json};
use hermeneia_ir::{Bond, Delta, Fate, Floor, Grade, Merge};
use std::collections::BTreeMap;
use std::fmt;

pub type TropeId = String;

/// A stored particular: a property-instance with a bearer, a context, and a
/// provenance record.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Trope {
    pub id: TropeId,
    pub quality: String,
    pub bearer: String,
    pub context: String,
    pub record: String,
}

/// A recorded transformation between particulars, carrying a DECLARED grade.
/// The store keeps grades; it does not compute them — Haec produces them.
#[derive(Clone, Debug)]
pub struct StoreEdge {
    pub id: String,
    pub effect: String,
    pub from: TropeId,
    pub to: TropeId,
    pub grade: Grade,
}

/// A maximal chain of transformations from a subject to a terminus.
#[derive(Clone, Debug)]
pub struct Path {
    pub edges: Vec<StoreEdge>,
    pub terminus: TropeId,
}

/// A named use-model: a partial demand vector over grade coordinates.
#[derive(Clone, Debug)]
pub struct UseModelDef {
    pub name: String,
    pub floor: Floor,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum StoreError {
    NotFound(String),
    Ambiguous {
        what: String,
        candidates: Vec<String>,
    },
    Malformed {
        line: usize,
        msg: String,
    },
    Io(String),
    /// The operation is part of the language but this store does not implement
    /// it. Reported honestly rather than returning an empty result.
    Unsupported(&'static str),
}

impl fmt::Display for StoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            StoreError::NotFound(w) => write!(f, "not found: {}", w),
            StoreError::Ambiguous { what, candidates } => write!(
                f,
                "ambiguous {}: {} candidates ({})",
                what,
                candidates.len(),
                candidates.join(", ")
            ),
            StoreError::Malformed { line, msg } => write!(f, "store line {}: {}", line, msg),
            StoreError::Io(m) => write!(f, "io: {}", m),
            StoreError::Unsupported(op) => {
                write!(f, "`{}` is not implemented by this store", op)
            }
        }
    }
}

impl std::error::Error for StoreError {}

/// The seam. Vocarium implements this; the JSONL stub below implements it now.
pub trait StoreProvider {
    fn get(&self, id: &str) -> Result<Trope, StoreError>;
    /// Find particulars by quality, optionally narrowed by context.
    fn find(&self, quality: &str, ctx: Option<&str>) -> Result<Vec<Trope>, StoreError>;
    /// Bounded neighbourhood: particulars reachable within `max_loss` in the
    /// retention order. The implementation owns the algebra cost.
    fn neighbours(&self, id: &str, max_loss: Delta) -> Result<Vec<Trope>, StoreError>;
    /// All maximal transformation paths leading out of `from`.
    fn paths_from(&self, from: &str) -> Result<Vec<Path>, StoreError>;
    /// Resolve a named use-model to its floor.
    fn use_model(&self, name: &str) -> Result<UseModelDef, StoreError>;
}

// ───────────────────────── the JSONL stub ─────────────────────────

/// A JSONL store. Each line is one record discriminated by `kind`:
/// `trope`, `edge`, or `use_model`.
#[derive(Debug, Default)]
pub struct JsonlStore {
    tropes: BTreeMap<TropeId, Trope>,
    edges: Vec<StoreEdge>,
    use_models: BTreeMap<String, UseModelDef>,
}

impl JsonlStore {
    pub fn load(src: &str) -> Result<JsonlStore, StoreError> {
        let mut s = JsonlStore::default();
        for (n, raw) in src.lines().enumerate() {
            let line = n + 1;
            let t = raw.trim();
            if t.is_empty() || t.starts_with('#') {
                continue;
            }
            let v = json::parse(t).map_err(|e| StoreError::Malformed { line, msg: e })?;
            let kind = v
                .get("kind")
                .and_then(Json::as_str)
                .ok_or(StoreError::Malformed {
                    line,
                    msg: "record has no 'kind'".into(),
                })?;
            match kind {
                "trope" => {
                    let t = parse_trope(&v).map_err(|msg| StoreError::Malformed { line, msg })?;
                    s.tropes.insert(t.id.clone(), t);
                }
                "edge" => {
                    let e = parse_edge(&v).map_err(|msg| StoreError::Malformed { line, msg })?;
                    s.edges.push(e);
                }
                "use_model" => {
                    let u =
                        parse_use_model(&v).map_err(|msg| StoreError::Malformed { line, msg })?;
                    s.use_models.insert(u.name.clone(), u);
                }
                other => {
                    return Err(StoreError::Malformed {
                        line,
                        msg: format!("unknown kind '{}'", other),
                    })
                }
            }
        }
        Ok(s)
    }

    pub fn load_file(path: &std::path::Path) -> Result<JsonlStore, StoreError> {
        let src = std::fs::read_to_string(path)
            .map_err(|e| StoreError::Io(format!("{}: {}", path.display(), e)))?;
        JsonlStore::load(&src)
    }

    /// The seed corpus: the README's own worked example, so that the
    /// documentation and the tests are one artefact.
    pub fn seed() -> JsonlStore {
        JsonlStore::load(SEED).expect("the embedded seed corpus must parse")
    }

    pub fn len(&self) -> usize {
        self.tropes.len()
    }
    pub fn is_empty(&self) -> bool {
        self.tropes.is_empty()
    }
}

pub const SEED: &str = include_str!("../corpus/seed.jsonl");

fn field<'a>(v: &'a Json, k: &str) -> Result<&'a str, String> {
    v.get(k)
        .and_then(Json::as_str)
        .ok_or_else(|| format!("missing string field '{}'", k))
}

fn parse_trope(v: &Json) -> Result<Trope, String> {
    Ok(Trope {
        id: field(v, "id")?.to_string(),
        quality: field(v, "quality")?.to_string(),
        bearer: field(v, "bearer")?.to_string(),
        context: field(v, "context")?.to_string(),
        record: field(v, "record")?.to_string(),
    })
}

fn parse_fate(v: &Json) -> Result<Fate, String> {
    Fate::from_json(v)
}

fn parse_grade(v: &Json) -> Result<Grade, String> {
    let f = v.get("fate").ok_or("grade missing 'fate'")?;
    let pick = |k: &str| -> Result<Fate, String> {
        match f.get(k) {
            Some(x) => parse_fate(x),
            None => Ok(Fate::Present),
        }
    };
    let bond = match v
        .get("bond")
        .and_then(|b| b.get("k"))
        .and_then(Json::as_str)
    {
        None | Some("Intact") => Bond::Intact,
        Some("Withheld") => Bond::Withheld,
        Some("Severed") => Bond::Severed,
        Some(other) => return Err(format!("unknown or deceptive bond '{}'", other)),
    };
    let merge = match v.get("merge") {
        None => Merge::Single,
        Some(m) => match m.get("k").and_then(Json::as_str) {
            Some("Single") | None => Merge::Single,
            Some("Fused") => Merge::Fused(
                m.get("tau")
                    .and_then(Json::as_str)
                    .ok_or("Fused merge missing required 'tau'")?
                    .to_string(),
            ),
            Some(other) => return Err(format!("unknown or deceptive merge '{}'", other)),
        },
    };
    Ok(Grade {
        quality: pick("quality")?,
        bearer: pick("bearer")?,
        context: pick("context")?,
        record: pick("record")?,
        bond,
        merge,
    })
}

fn parse_edge(v: &Json) -> Result<StoreEdge, String> {
    Ok(StoreEdge {
        id: field(v, "id")?.to_string(),
        effect: field(v, "effect")?.to_string(),
        from: field(v, "from")?.to_string(),
        to: field(v, "to")?.to_string(),
        grade: parse_grade(v.get("grade").ok_or("edge missing 'grade'")?)?,
    })
}

fn parse_use_model(v: &Json) -> Result<UseModelDef, String> {
    let floor_v = v.get("floor").ok_or("use_model missing 'floor'")?;
    let mut floor = Floor::default();
    if let Some(f) = floor_v.get("fate") {
        if let Some(x) = f.get("quality") {
            floor.quality = Some(parse_fate(x)?);
        }
        if let Some(x) = f.get("bearer") {
            floor.bearer = Some(parse_fate(x)?);
        }
        if let Some(x) = f.get("context") {
            floor.context = Some(parse_fate(x)?);
        }
        if let Some(x) = f.get("record") {
            floor.record = Some(parse_fate(x)?);
        }
    }
    if let Some(b) = floor_v
        .get("bond")
        .and_then(|b| b.get("k"))
        .and_then(Json::as_str)
    {
        floor.bond = Some(match b {
            "Intact" => Bond::Intact,
            "Withheld" => Bond::Withheld,
            "Severed" => Bond::Severed,
            other => return Err(format!("unknown or deceptive bond in floor: '{}'", other)),
        });
    }
    if floor.is_empty() {
        return Err("floor declares no demand; the schema requires at least one".into());
    }
    Ok(UseModelDef {
        name: field(v, "name")?.to_string(),
        floor,
    })
}

impl StoreProvider for JsonlStore {
    fn get(&self, id: &str) -> Result<Trope, StoreError> {
        self.tropes
            .get(id)
            .cloned()
            .ok_or_else(|| StoreError::NotFound(format!("trope '{}'", id)))
    }

    fn find(&self, quality: &str, ctx: Option<&str>) -> Result<Vec<Trope>, StoreError> {
        Ok(self
            .tropes
            .values()
            .filter(|t| t.quality == quality)
            .filter(|t| ctx.is_none_or(|c| t.context == c))
            .cloned()
            .collect())
    }

    fn neighbours(&self, _id: &str, _max_loss: Delta) -> Result<Vec<Trope>, StoreError> {
        // Bounded traversal needs the retention order, which lives in
        // trope-checker. Slice v1 does not implement `evoke`, so this reports
        // the gap rather than silently returning nothing. See docs/SPEC.adoc.
        Err(StoreError::Unsupported("evoke (bounded neighbourhood)"))
    }

    fn paths_from(&self, from: &str) -> Result<Vec<Path>, StoreError> {
        if !self.tropes.contains_key(from) {
            return Err(StoreError::NotFound(format!("trope '{}'", from)));
        }
        // Maximal chains, walking forward. The seed corpus is a small DAG; the
        // visited set guards against a malformed cyclic store.
        let mut out = Vec::new();
        let mut stack: Vec<(Vec<StoreEdge>, String, Vec<String>)> =
            vec![(Vec::new(), from.to_string(), vec![from.to_string()])];
        while let Some((acc, at, seen)) = stack.pop() {
            let nexts: Vec<&StoreEdge> = self
                .edges
                .iter()
                .filter(|e| e.from == at && !seen.contains(&e.to))
                .collect();
            if nexts.is_empty() {
                if !acc.is_empty() {
                    out.push(Path {
                        edges: acc,
                        terminus: at,
                    });
                }
                continue;
            }
            for e in nexts {
                let mut a = acc.clone();
                a.push((*e).clone());
                let mut s = seen.clone();
                s.push(e.to.clone());
                stack.push((a, e.to.clone(), s));
            }
        }
        Ok(out)
    }

    fn use_model(&self, name: &str) -> Result<UseModelDef, StoreError> {
        self.use_models
            .get(name)
            .cloned()
            .ok_or_else(|| StoreError::NotFound(format!("use-model '{}'", name)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seed_corpus_loads() {
        let s = JsonlStore::seed();
        assert!(!s.is_empty(), "seed corpus must contain particulars");
    }

    #[test]
    fn finds_the_readme_subject() {
        let s = JsonlStore::seed();
        let hits = s.find("authentic language", None).unwrap();
        assert_eq!(hits.len(), 1, "the README subject must resolve uniquely");
        assert_eq!(hits[0].bearer, "Paul de Man");
    }

    #[test]
    fn the_subject_has_exactly_one_path() {
        let s = JsonlStore::seed();
        let subj = &s.find("authentic language", None).unwrap()[0];
        let paths = s.paths_from(&subj.id).unwrap();
        assert_eq!(paths.len(), 1);
        assert_eq!(paths[0].edges.len(), 1);
    }

    #[test]
    fn use_model_resolves_to_a_partial_floor() {
        let s = JsonlStore::seed();
        let u = s.use_model("critical-paraphrase").unwrap();
        assert!(
            u.floor.quality.is_some(),
            "must demand something of quality"
        );
        assert!(
            u.floor.bearer.is_none(),
            "an omitted coordinate must impose NO demand"
        );
    }

    #[test]
    fn unknown_use_model_is_not_found() {
        let s = JsonlStore::seed();
        assert!(matches!(
            s.use_model("no-such-model"),
            Err(StoreError::NotFound(_))
        ));
    }

    #[test]
    fn evoke_is_unsupported_not_silently_empty() {
        let s = JsonlStore::seed();
        assert!(matches!(
            s.neighbours("t_authentic_language", Delta::Q(3)),
            Err(StoreError::Unsupported(_))
        ));
    }

    #[test]
    fn malformed_line_reports_its_number() {
        let src = "{\"kind\":\"trope\",\"id\":\"a\",\"quality\":\"q\",\"bearer\":\"b\",\"context\":\"c\",\"record\":\"r\"}\nnot json\n";
        match JsonlStore::load(src) {
            Err(StoreError::Malformed { line, .. }) => assert_eq!(line, 2),
            other => panic!("expected Malformed on line 2, got {:?}", other),
        }
    }

    #[test]
    fn deceptive_grade_is_rejected_by_the_loader() {
        let src = r#"{"kind":"edge","id":"e","effect":"attenuate","from":"a","to":"b","grade":{"fate":{"quality":{"k":"Falsified"}}}}"#;
        assert!(matches!(
            JsonlStore::load(src),
            Err(StoreError::Malformed { .. })
        ));
    }
}
