// SPDX-FileCopyrightText: © 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// SPDX-License-Identifier: MPL-2.0
//
// Query planning: a parsed voke expression plus a store become a Trope IR
// document. The planner never composes or compares grades — it lays out the
// DAG and lets trope-checker do the algebra. See docs/SPEC.adoc.

use hermeneia_ir::{Document, Edge, Node, UseModel};
use hermeneia_store::{StoreError, StoreProvider};
use hermeneia_syntax::{Invoke, Query, Show};
use std::fmt;

#[derive(Debug)]
pub enum PlanError {
    Store(StoreError),
    /// The subject resolved to no particular.
    NoSubject(String),
    /// The subject resolved to several; the query must be narrowed.
    AmbiguousSubject {
        quality: String,
        ids: Vec<String>,
    },
    /// The subject has no recorded transformation path, so there is nothing to
    /// judge: a use-model asks what the particular becomes, and it becomes
    /// nothing here.
    NoPath(String),
    /// Several paths lead out of the subject. Choosing between them is
    /// `intervoke`, which slice v1 does not implement.
    AmbiguousPath {
        subject: String,
        count: usize,
    },
    /// The emitted IR failed the structural checks.
    Ir(String),
    /// Asked to show something this build cannot honestly produce.
    CannotShow(Show, &'static str),
}

impl fmt::Display for PlanError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PlanError::Store(e) => write!(f, "{}", e),
            PlanError::NoSubject(q) => write!(f, "no particular has quality \"{}\"", q),
            PlanError::AmbiguousSubject { quality, ids } => write!(
                f,
                "\"{}\" resolves to {} particulars ({}); narrow it with `within context`",
                quality,
                ids.len(),
                ids.join(", ")
            ),
            PlanError::NoPath(s) => write!(
                f,
                "\"{}\" has no recorded transformation path, so there is nothing to judge under a use-model",
                s
            ),
            PlanError::AmbiguousPath { subject, count } => write!(
                f,
                "\"{}\" has {} candidate paths; choosing between them is `intervoke`, \
                 which is not implemented in this build",
                subject, count
            ),
            PlanError::Ir(m) => write!(f, "emitted IR is invalid: {}", m),
            PlanError::CannotShow(s, why) => write!(f, "cannot show `{}`: {}", s.as_str(), why),
        }
    }
}

impl std::error::Error for PlanError {}

impl From<StoreError> for PlanError {
    fn from(e: StoreError) -> Self {
        PlanError::Store(e)
    }
}

/// The result of planning: the IR to hand to the checker, plus what the query
/// asked to see.
pub struct Plan {
    pub document: Document,
    pub show: Vec<Show>,
    pub subject: String,
    pub use_model: String,
    pub terminus: String,
}

/// Plan any supported query.
pub fn plan<S: StoreProvider>(store: &S, query: &Query) -> Result<Plan, PlanError> {
    match query {
        Query::Invoke(i) => plan_invoke(store, i),
    }
}

/// `invoke` — call a particular into a declared use.
///
/// Resolve the subject, resolve the use-model to a floor, take the recorded
/// transformation path, and lay it out as a DAG whose output node is the
/// path's terminus. The verdict is then `floor ⊑ acc(terminus)`, computed by
/// the checker.
fn plan_invoke<S: StoreProvider>(store: &S, q: &Invoke) -> Result<Plan, PlanError> {
    // `show loss` needs the per-dimension residue vector, which the checker CLI
    // does not emit (it prints one witness edge and coordinate). Refusing is
    // honest; inventing a vector would not be. See docs/SPEC.adoc.
    if let Some(s) = q.show.iter().find(|s| matches!(s, Show::Loss)) {
        return Err(PlanError::CannotShow(
            *s,
            "the checker CLI reports a witness edge and coordinate, not the full \
             per-dimension loss vector",
        ));
    }
    if let Some(s) = q.show.iter().find(|s| matches!(s, Show::Warrant)) {
        return Err(PlanError::CannotShow(
            *s,
            "warrants require the warrant graph, which arrives with `revoke`",
        ));
    }

    let hits = store.find(&q.subject, None)?;
    let subject = match hits.len() {
        0 => return Err(PlanError::NoSubject(q.subject.clone())),
        1 => hits.into_iter().next().expect("length checked"),
        _ => {
            return Err(PlanError::AmbiguousSubject {
                quality: q.subject.clone(),
                ids: hits.into_iter().map(|t| t.id).collect(),
            })
        }
    };

    let um = store.use_model(&q.use_model)?;

    let mut paths = store.paths_from(&subject.id)?;
    let path = match paths.len() {
        0 => return Err(PlanError::NoPath(q.subject.clone())),
        1 => paths.pop().expect("length checked"),
        n => {
            return Err(PlanError::AmbiguousPath {
                subject: q.subject.clone(),
                count: n,
            })
        }
    };

    // Lay out the DAG. Every node on the path becomes a Trope node; every
    // recorded transformation becomes an edge carrying its declared grade.
    let mut nodes = vec![Node::trope(
        subject.id.clone(),
        Some(subject.quality.clone()),
    )];
    let mut edges = Vec::new();
    for e in &path.edges {
        let to = store.get(&e.to)?;
        nodes.push(Node::trope(to.id.clone(), Some(to.quality.clone())));
        edges.push(Edge {
            id: e.id.clone(),
            effect: e.effect.clone(),
            inputs: vec![e.from.clone()],
            output: e.to.clone(),
            grade: e.grade.clone(),
        });
    }

    let document = Document {
        nodes,
        edges,
        use_model: UseModel {
            id: None,
            label: Some(um.name.clone()),
            output: path.terminus.clone(),
            floor: um.floor.clone(),
        },
    };

    // Catch a malformed emission here, as a Hermeneia bug, rather than letting
    // it surface downstream as a `validation-fault` exit from the checker.
    document.validate().map_err(PlanError::Ir)?;

    Ok(Plan {
        document,
        show: q.show.clone(),
        subject: q.subject.clone(),
        use_model: q.use_model.clone(),
        terminus: path.terminus,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use hermeneia_store::JsonlStore;
    use hermeneia_syntax::parse;

    fn plan_src(src: &str) -> Result<Plan, PlanError> {
        let store = JsonlStore::seed();
        let q = parse(src).expect("test query must parse");
        plan(&store, &q)
    }

    #[test]
    fn plans_the_readme_example() {
        let p = plan_src(
            "invoke \"authentic language\" under use_model \"critical-paraphrase\" show verdict",
        )
        .expect("should plan");
        assert_eq!(p.document.nodes.len(), 2);
        assert_eq!(p.document.edges.len(), 1);
        assert_eq!(p.document.edges[0].effect, "attenuate");
        assert_eq!(p.terminus, "t_real_language");
        assert_eq!(p.document.use_model.output, "t_real_language");
    }

    #[test]
    fn emitted_ir_is_structurally_valid() {
        let p = plan_src(
            "invoke \"authentic language\" under use_model \"critical-paraphrase\" show verdict",
        )
        .unwrap();
        assert!(p.document.validate().is_ok());
    }

    #[test]
    fn floor_omits_undemanded_coordinates() {
        let p = plan_src(
            "invoke \"authentic language\" under use_model \"critical-paraphrase\" show verdict",
        )
        .unwrap();
        let f = &p.document.use_model.floor;
        assert!(f.quality.is_some());
        assert!(f.bearer.is_none() && f.context.is_none() && f.record.is_none());
    }

    #[test]
    fn unknown_subject_is_reported() {
        assert!(matches!(
            plan_src(
                "invoke \"no such quality\" under use_model \"critical-paraphrase\" show verdict"
            ),
            Err(PlanError::NoSubject(_))
        ));
    }

    #[test]
    fn unknown_use_model_is_reported() {
        assert!(matches!(
            plan_src("invoke \"authentic language\" under use_model \"nope\" show verdict"),
            Err(PlanError::Store(StoreError::NotFound(_)))
        ));
    }

    #[test]
    fn show_loss_is_refused_honestly() {
        match plan_src(
            "invoke \"authentic language\" under use_model \"critical-paraphrase\" show loss",
        ) {
            Err(PlanError::CannotShow(Show::Loss, _)) => {}
            other => panic!("expected an honest refusal, got {:?}", other.err()),
        }
    }

    #[test]
    fn a_terminus_with_no_path_is_reported() {
        // The paraphrase is a terminus: nothing leads out of it.
        let store = JsonlStore::seed();
        let q =
            parse("invoke \"real language\" under use_model \"critical-paraphrase\" show verdict")
                .unwrap();
        assert!(matches!(plan(&store, &q), Err(PlanError::NoPath(_))));
    }
}
