// SPDX-FileCopyrightText: © 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// SPDX-License-Identifier: MPL-2.0
//
// Trope IR v0.2 — the integration contract with trope-checker.
//
// This crate MODELS and SERIALISES grades. It deliberately does NOT implement
// the grade algebra: there is no `compose` and no ordering here. Composition
// (▷) and the retention order (⊑) are proved in Idris2 inside trope-checker and
// are computed there, by `tropecheck`. Adding them here would fork the exact
// semantics the design exists to protect. See docs/SPEC.adoc §"What Hermeneia
// must not do".
//
// The wire encodings below were read from
// trope-checker/schemas/trope-ir.schema.json (byte-identical to
// haec/design/trope-ir.schema.json) rather than recalled.

pub mod json;

use json::Json;

pub const IR_VERSION: &str = "0.2";
pub const IR_PROFILE: &str = "prevent";

/// Fidelity: δ ∈ ℕ ∪ {∞, ⊤}. Finite δ is tropical (min-plus) quantified loss;
/// `Inf` is total quantified loss; `Top` is loss of an UNKNOWN amount and is
/// the bottom of the retention order — the honest answer, not a failure.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Delta {
    Q(u32),
    Inf,
    Top,
}

impl Delta {
    fn to_json(self) -> Json {
        match self {
            Delta::Q(n) => Json::Num(n as i64),
            Delta::Inf => Json::str("inf"),
            Delta::Top => Json::str("top"),
        }
    }
    pub fn from_json(v: &Json) -> Result<Delta, String> {
        match v {
            Json::Num(n) if *n >= 0 => Ok(Delta::Q(*n as u32)),
            Json::Str(s) if s == "inf" => Ok(Delta::Inf),
            Json::Str(s) if s == "top" => Ok(Delta::Top),
            other => Err(format!("bad delta: {:?}", other)),
        }
    }
}

/// A field-fate. `Falsified` is absent by construction: it is the deceptive
/// inhabitant, excluded by the `prevent` profile, so Hermeneia cannot emit one
/// even by accident.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Fate {
    Present,
    Attenuated(Delta),
    Predicated(String),
    Dropped,
}

impl Fate {
    fn to_json(&self) -> Json {
        match self {
            Fate::Present => Json::obj(vec![("k", Json::str("Present"))]),
            Fate::Attenuated(d) => {
                Json::obj(vec![("k", Json::str("Attenuated")), ("delta", d.to_json())])
            }
            Fate::Predicated(p) => Json::obj(vec![
                ("k", Json::str("Predicated")),
                ("predicate", Json::str(p.clone())),
            ]),
            Fate::Dropped => Json::obj(vec![("k", Json::str("Dropped"))]),
        }
    }
    pub fn from_json(v: &Json) -> Result<Fate, String> {
        let k = v
            .get("k")
            .and_then(Json::as_str)
            .ok_or("fate missing 'k'")?;
        match k {
            "Present" => Ok(Fate::Present),
            "Dropped" => Ok(Fate::Dropped),
            "Attenuated" => {
                let d = v.get("delta").ok_or("Attenuated missing 'delta'")?;
                Ok(Fate::Attenuated(Delta::from_json(d)?))
            }
            "Predicated" => {
                let p = v
                    .get("predicate")
                    .and_then(Json::as_str)
                    .ok_or("Predicated missing 'predicate'")?;
                Ok(Fate::Predicated(p.to_string()))
            }
            "Falsified" => {
                Err("deceptive fate 'Falsified' is excluded under the prevent profile".into())
            }
            other => Err(format!("unknown fate kind '{}'", other)),
        }
    }
}

/// Bond. `Misbound` (deceptive) is excluded under `prevent`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Bond {
    Intact,
    Withheld,
    Severed,
}

impl Bond {
    fn to_json(self) -> Json {
        let k = match self {
            Bond::Intact => "Intact",
            Bond::Withheld => "Withheld",
            Bond::Severed => "Severed",
        };
        Json::obj(vec![("k", Json::str(k))])
    }
}

/// Merge. A `Fused` merge carries a REQUIRED provenance tag τ — an untagged
/// merge does not elaborate. `Conflated` (deceptive) is excluded under `prevent`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Merge {
    Single,
    Fused(String),
}

impl Merge {
    fn to_json(&self) -> Json {
        match self {
            Merge::Single => Json::obj(vec![("k", Json::str("Single"))]),
            Merge::Fused(tau) => Json::obj(vec![
                ("k", Json::str("Fused")),
                ("tau", Json::str(tau.clone())),
            ]),
        }
    }
}

/// The six-coordinate loss-shape grade: four field-fates over
/// Φ = {quality, bearer, context, record}, plus bond and merge.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Grade {
    pub quality: Fate,
    pub bearer: Fate,
    pub context: Fate,
    pub record: Fate,
    pub bond: Bond,
    pub merge: Merge,
}

impl Grade {
    /// ε — full presence on every field, intact bond, no merge.
    pub fn epsilon() -> Grade {
        Grade {
            quality: Fate::Present,
            bearer: Fate::Present,
            context: Fate::Present,
            record: Fate::Present,
            bond: Bond::Intact,
            merge: Merge::Single,
        }
    }
    fn to_json(&self) -> Json {
        Json::obj(vec![
            (
                "fate",
                Json::obj(vec![
                    ("quality", self.quality.to_json()),
                    ("bearer", self.bearer.to_json()),
                    ("context", self.context.to_json()),
                    ("record", self.record.to_json()),
                ]),
            ),
            ("bond", self.bond.to_json()),
            ("merge", self.merge.to_json()),
        ])
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NodeType {
    Trope,
    FloatingQuality,
    Codomain,
}

impl NodeType {
    fn as_str(self) -> &'static str {
        match self {
            NodeType::Trope => "Trope",
            NodeType::FloatingQuality => "FloatingQuality",
            NodeType::Codomain => "Codomain",
        }
    }
}

#[derive(Clone, Debug)]
pub struct Node {
    pub id: String,
    pub ntype: NodeType,
    pub present: Vec<String>,
    pub label: Option<String>,
}

impl Node {
    pub fn trope(id: impl Into<String>, label: Option<String>) -> Node {
        Node {
            id: id.into(),
            ntype: NodeType::Trope,
            present: ["quality", "bearer", "context", "record"]
                .iter()
                .map(|s| s.to_string())
                .collect(),
            label,
        }
    }
    fn to_json(&self) -> Json {
        let mut pairs = vec![
            ("id", Json::str(self.id.clone())),
            ("type", Json::str(self.ntype.as_str())),
            (
                "present",
                Json::Arr(self.present.iter().map(|f| Json::str(f.clone())).collect()),
            ),
        ];
        if let Some(l) = &self.label {
            pairs.push(("label", Json::str(l.clone())));
        }
        Json::obj(pairs)
    }
}

#[derive(Clone, Debug)]
pub struct Edge {
    pub id: String,
    pub effect: String,
    pub inputs: Vec<String>,
    pub output: String,
    pub grade: Grade,
}

impl Edge {
    fn to_json(&self) -> Json {
        Json::obj(vec![
            ("id", Json::str(self.id.clone())),
            ("effect", Json::str(self.effect.clone())),
            (
                "inputs",
                Json::Arr(self.inputs.iter().map(|i| Json::str(i.clone())).collect()),
            ),
            ("output", Json::str(self.output.clone())),
            ("grade", self.grade.to_json()),
        ])
    }
}

/// A partial demand vector. Every coordinate is optional; an omitted coordinate
/// imposes NO demand. This is what a use-model *is*.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Floor {
    pub quality: Option<Fate>,
    pub bearer: Option<Fate>,
    pub context: Option<Fate>,
    pub record: Option<Fate>,
    pub bond: Option<Bond>,
    pub merge: Option<Merge>,
}

impl Floor {
    pub fn is_empty(&self) -> bool {
        self.quality.is_none()
            && self.bearer.is_none()
            && self.context.is_none()
            && self.record.is_none()
            && self.bond.is_none()
            && self.merge.is_none()
    }
    fn to_json(&self) -> Json {
        let mut fate = Vec::new();
        if let Some(f) = &self.quality {
            fate.push(("quality", f.to_json()));
        }
        if let Some(f) = &self.bearer {
            fate.push(("bearer", f.to_json()));
        }
        if let Some(f) = &self.context {
            fate.push(("context", f.to_json()));
        }
        if let Some(f) = &self.record {
            fate.push(("record", f.to_json()));
        }
        let mut pairs = Vec::new();
        if !fate.is_empty() {
            pairs.push(("fate", Json::obj(fate)));
        }
        if let Some(b) = self.bond {
            pairs.push(("bond", b.to_json()));
        }
        if let Some(m) = &self.merge {
            pairs.push(("merge", m.to_json()));
        }
        Json::obj(pairs)
    }
}

#[derive(Clone, Debug)]
pub struct UseModel {
    pub id: Option<String>,
    pub label: Option<String>,
    /// The node whose accumulated grade is checked against the floor.
    pub output: String,
    pub floor: Floor,
}

impl UseModel {
    fn to_json(&self) -> Json {
        let mut pairs = vec![
            ("output", Json::str(self.output.clone())),
            ("floor", self.floor.to_json()),
        ];
        if let Some(i) = &self.id {
            pairs.push(("id", Json::str(i.clone())));
        }
        if let Some(l) = &self.label {
            pairs.push(("label", Json::str(l.clone())));
        }
        Json::obj(pairs)
    }
}

#[derive(Clone, Debug)]
pub struct Document {
    pub nodes: Vec<Node>,
    pub edges: Vec<Edge>,
    pub use_model: UseModel,
}

impl Document {
    pub fn to_json(&self) -> Json {
        Json::obj(vec![
            ("version", Json::str(IR_VERSION)),
            ("profile", Json::str(IR_PROFILE)),
            (
                "nodes",
                Json::Arr(self.nodes.iter().map(Node::to_json).collect()),
            ),
            (
                "edges",
                Json::Arr(self.edges.iter().map(Edge::to_json).collect()),
            ),
            ("use_model", self.use_model.to_json()),
        ])
    }

    pub fn emit(&self) -> String {
        json::write(&self.to_json())
    }

    /// Structural checks mirroring the constraints the schema enforces, so that
    /// a malformed emission is caught here as a Hermeneia bug rather than
    /// surfacing downstream as a `validation-fault` exit from the checker.
    ///
    /// Read from the schema's conditional `allOf`: `fuse` takes EXACTLY two
    /// inputs and a `Fused` merge with a τ tag; every other effect takes
    /// EXACTLY one. `edge.inputs` has `maxItems: 2` globally.
    pub fn validate(&self) -> Result<(), String> {
        if self.nodes.is_empty() {
            return Err("IR has no nodes".into());
        }
        if self.use_model.floor.is_empty() {
            return Err("floor has no coordinates; schema requires minProperties 1".into());
        }
        let ids: Vec<&str> = self.nodes.iter().map(|n| n.id.as_str()).collect();
        if !ids.contains(&self.use_model.output.as_str()) {
            return Err(format!(
                "use_model.output '{}' is not a node id",
                self.use_model.output
            ));
        }
        for e in &self.edges {
            let n = e.inputs.len();
            if e.effect == "fuse" {
                if n != 2 {
                    return Err(format!(
                        "edge '{}': fuse requires exactly 2 inputs, got {}",
                        e.id, n
                    ));
                }
                if !matches!(e.grade.merge, Merge::Fused(_)) {
                    return Err(format!(
                        "edge '{}': fuse requires a Fused merge with a tau tag",
                        e.id
                    ));
                }
            } else if n != 1 {
                return Err(format!(
                    "edge '{}': effect '{}' requires exactly 1 input, got {}",
                    e.id, e.effect, n
                ));
            }
            for i in &e.inputs {
                if !ids.contains(&i.as_str()) {
                    return Err(format!("edge '{}': input '{}' is not a node id", e.id, i));
                }
            }
            if !ids.contains(&e.output.as_str()) {
                return Err(format!(
                    "edge '{}': output '{}' is not a node id",
                    e.id, e.output
                ));
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn doc() -> Document {
        Document {
            nodes: vec![Node::trope("a", None), Node::trope("b", None)],
            edges: vec![Edge {
                id: "e1".into(),
                effect: "attenuate".into(),
                inputs: vec!["a".into()],
                output: "b".into(),
                grade: Grade {
                    quality: Fate::Attenuated(Delta::Q(6)),
                    ..Grade::epsilon()
                },
            }],
            use_model: UseModel {
                id: None,
                label: None,
                output: "b".into(),
                floor: Floor {
                    quality: Some(Fate::Attenuated(Delta::Q(3))),
                    ..Floor::default()
                },
            },
        }
    }

    #[test]
    fn emits_required_top_level_keys() {
        let v = doc().to_json();
        for k in ["version", "profile", "nodes", "edges", "use_model"] {
            assert!(v.get(k).is_some(), "missing top-level key {}", k);
        }
        assert_eq!(v.get("version").unwrap().as_str(), Some("0.2"));
        assert_eq!(v.get("profile").unwrap().as_str(), Some("prevent"));
    }

    #[test]
    fn valid_document_validates() {
        assert!(doc().validate().is_ok());
    }

    #[test]
    fn rejects_wrong_arity_for_non_fuse() {
        let mut d = doc();
        d.edges[0].inputs.push("a".into());
        assert!(d.validate().unwrap_err().contains("exactly 1 input"));
    }

    #[test]
    fn rejects_fuse_without_tau() {
        let mut d = doc();
        d.edges[0].effect = "fuse".into();
        d.edges[0].inputs = vec!["a".into(), "b".into()];
        assert!(d.validate().unwrap_err().contains("Fused merge"));
    }

    #[test]
    fn rejects_empty_floor() {
        let mut d = doc();
        d.use_model.floor = Floor::default();
        assert!(d.validate().is_err());
    }

    #[test]
    fn deceptive_fate_is_unrepresentable_from_wire() {
        let v = json::parse(r#"{"k":"Falsified"}"#).unwrap();
        assert!(Fate::from_json(&v).unwrap_err().contains("prevent"));
    }

    #[test]
    fn delta_top_round_trips() {
        let f = Fate::Attenuated(Delta::Top);
        let back = Fate::from_json(&f.to_json()).unwrap();
        assert_eq!(f, back);
    }
}
