//! The engine's own suite: a workspace opened on a tempdir, the kits
//! declared, statements of the language run through a channel, reads
//! streamed, the brief counted, a ruling landed. Needs the extension
//! beside this checkout (`GLOSSQL_EXTENSION` overrides the path).

use glossdb_duck::{
    Actor, ActorKind, Config, Outcome, Plane, SessionError, call_shape, rows_as_text,
};

fn agent() -> Actor {
    Actor {
        kind: ActorKind::Agent,
        id: "test:agent".into(),
    }
}

fn human() -> Actor {
    Actor {
        kind: ActorKind::Human,
        id: "test:human".into(),
    }
}

/// The extension beside this checkout, or where `GLOSSQL_EXTENSION`
/// points. A build without one — CI, until the extension ships as an
/// artifact — runs none of this suite and says so.
fn extension_present() -> bool {
    let present = Config::laptop(std::path::Path::new(".")).extension.exists();
    if !present {
        eprintln!(
            "skipped: no glossql extension beside this checkout (GLOSSQL_EXTENSION overrides)"
        );
    }
    present
}

async fn plane() -> (tempfile::TempDir, Plane) {
    let dir = tempfile::tempdir().expect("a tempdir");
    let plane = Plane::open(Config::laptop(dir.path()))
        .await
        .expect("the workspace opens");
    (dir, plane)
}

fn text(outcomes: &[Outcome]) -> Vec<Vec<Option<String>>> {
    match outcomes.last() {
        Some(Outcome::Rows { batches, .. }) => rows_as_text(batches),
        other => panic!("rows expected, got {other:?}"),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn the_language_runs_through_a_channel_and_the_record_reads_back() {
    if !extension_present() {
        return;
    }
    let (_dir, plane) = plane().await;
    assert!(plane.datasets().await.unwrap().is_empty());
    assert_eq!(plane.brief_counts().await.unwrap().human_writings, 0);

    let session = plane.channel(agent(), None).await.unwrap();
    let outcomes = session
        .execute(
            "DECLARE DATASET fin SET (purpose: 'the engine suite');
             USE fin;
             CREATE TABLE fin.orders AS SELECT i AS id, i * 1.5 AS amount FROM range(4) t(i);
             GLOSS role ON orders.amount AS $${\"value\": \"measure\"}$$;",
        )
        .await
        .unwrap();
    assert_eq!(outcomes.len(), 4);
    assert!(
        matches!(&outcomes[0], Outcome::Done(t) if t.contains("fin")),
        "{:?}",
        outcomes[0]
    );
    assert!(
        matches!(&outcomes[3], Outcome::Done(t) if t.contains("role")),
        "{:?}",
        outcomes[3]
    );

    assert_eq!(plane.datasets().await.unwrap(), vec!["fin".to_string()]);
    assert!(plane.dataset_exists("fin").await.unwrap());
    assert!(!plane.dataset_exists("nope").await.unwrap());

    let bound = plane.channel(agent(), Some("fin")).await.unwrap();
    let read = bound
        .execute("SELECT subject, aspect, value FROM GLOSSARY(orders.amount)")
        .await
        .unwrap();
    let rows = text(&read);
    assert!(
        rows.iter().any(|r| r[1].as_deref() == Some("role")),
        "{rows:?}"
    );

    // A page is cut one row past the cap; a record read never is.
    let page = bound.query_page("SELECT * FROM fin.orders").await.unwrap();
    assert_eq!(page.cap, 200);
    assert!(!page.record);
    let whole = bound.query_page("SELECT * FROM glossary").await.unwrap();
    assert_eq!(whole.cap, usize::MAX);
    assert!(whole.record);
    assert!(matches!(
        bound.query_stream("SELECT 1; SELECT 2").await,
        Err(SessionError::NotOneRead)
    ));

    // A write answers its count; a refusal in a sequence names its place.
    let affected = bound
        .execute("DELETE FROM fin.orders WHERE id = 3")
        .await
        .unwrap();
    assert!(matches!(affected[0], Outcome::Affected(1)), "{affected:?}");
    let refused = bound.execute("SELECT 1; SELECT * FROM fin.nowhere").await;
    match refused {
        Err(SessionError::Sequence {
            index,
            total,
            landed,
            ..
        }) => {
            assert_eq!((index, total, landed.len()), (2, 2, 1));
        }
        other => panic!("{other:?}"),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_ruling_lands_under_human_standing_and_the_brief_counts_it() {
    if !extension_present() {
        return;
    }
    let (_dir, plane) = plane().await;
    plane
        .execute(
            agent(),
            None,
            "DECLARE DATASET fin SET (purpose: 'rulings')",
        )
        .await
        .unwrap();
    plane
        .execute(
            agent(),
            Some("fin"),
            "CREATE TABLE fin.orders AS SELECT i AS id FROM range(3) t(i);
             GLOSS meaning ON orders.id AS $${\"value\": \"the row's number\"}$$;",
        )
        .await
        .unwrap();
    let before = plane.brief_counts().await.unwrap();
    assert_eq!(before.human_writings, 0);

    let session = plane.channel(human(), Some("fin")).await.unwrap();
    let said = glossdb_duck::rulings::land(
        &session,
        glossdb_duck::rulings::Ruling {
            subject: "orders.id",
            aspect: "meaning",
            dimension: "scope",
            key: "k1",
            assumption: "ids are contiguous",
            stance: "confirmed",
            note: None,
        },
    )
    .await
    .unwrap();
    assert!(said.starts_with("ruled (confirmed) on `k1`"), "{said}");

    let after = plane.brief_counts().await.unwrap();
    assert_eq!(after.human_writings, 1);
    assert!(after.latest_human_at.is_some());
    assert_eq!(after.rulings_owed, 0);

    let shape = call_shape("USE fin; SELECT * FROM glossary");
    assert!(
        shape.reviews && !shape.writes,
        "a record read under USE reviews: {shape:?}"
    );
    assert_eq!(shape.dataset.as_deref(), Some("fin"));
    assert!(
        call_shape("SELECT * FROM GLOSSARY(orders)").reviews
            || !call_shape("SELECT * FROM GLOSSARY(orders)").writes
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn a_second_open_changes_nothing_and_the_derived_reads_stand() {
    if !extension_present() {
        return;
    }
    let dir = tempfile::tempdir().expect("a tempdir");
    async fn count(plane: &Plane) -> String {
        let rows = text(
            &plane
                .execute(agent(), None, "SELECT count(*) FROM glossql.aspects")
                .await
                .unwrap(),
        );
        rows[0][0].clone().unwrap()
    }
    let first = Plane::open(Config::laptop(dir.path()))
        .await
        .expect("the workspace opens");
    let session = first.channel(agent(), None).await.unwrap();
    session
        .execute(
            "DECLARE DATASET fin SET (purpose: 'reads');
             USE fin;
             DECLARE ASPECT dso WITH $${\"title\": \"DSO\"}$$ AS QUERY;
             GLOSS dso ON fin AS $${\"sql\": \"SELECT 1 AS value\", \"assumptions\": [
               {\"dimension\": \"definition\", \"key\": \"per-line\", \"assumption\": \"per line\", \"basis\": \"judgment\", \"confidence\": 0.7},
               {\"dimension\": \"grain\", \"key\": \"g\", \"assumption\": \"monthly\", \"basis\": \"measured\", \"confidence\": 1.0}]}$$;",
        )
        .await
        .unwrap();
    let open = text(
        &session
            .execute("SELECT key, conf, sibling FROM open_questions")
            .await
            .unwrap(),
    );
    assert_eq!(open.len(), 1, "{open:?}");
    assert_eq!(open[0][0].as_deref(), Some("per-line"));
    let bound = text(
        &session
            .execute("SELECT dataset FROM current_dataset")
            .await
            .unwrap(),
    );
    assert_eq!(bound, vec![vec![Some("fin".to_string())]]);
    drop(session);
    let declared = count(&first).await;
    drop(first);

    let second = Plane::open(Config::laptop(dir.path()))
        .await
        .expect("the workspace reopens");
    assert_eq!(
        count(&second).await,
        declared,
        "a second open declares nothing twice"
    );
    let unbound = text(
        &second
            .execute(agent(), None, "SELECT dataset FROM current_dataset")
            .await
            .unwrap(),
    );
    assert!(
        unbound.is_empty(),
        "an unbound channel serves no row: {unbound:?}"
    );
}

/// This repository's kits' suites, `kits/<kit>/kit.test`, on the
/// engine, each on a lake of its own.
#[test]
fn the_kits_suites_pass() {
    if !extension_present() {
        return;
    }
    let kits = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../kits");
    let mut suites: Vec<_> = std::fs::read_dir(&kits)
        .expect("the kits directory")
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path().join("kit.test"))
        .filter(|suite| suite.exists())
        .collect();
    suites.sort();
    assert!(!suites.is_empty(), "no suite under {}", kits.display());
    for suite in suites {
        let dir = tempfile::tempdir().expect("a tempdir");
        let records = glossdb_duck::sqllogic::run_suite(&suite, dir.path())
            .unwrap_or_else(|report| panic!("{report}"));
        eprintln!("{}: {records} records", suite.display());
    }
}
