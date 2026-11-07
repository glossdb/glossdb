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

/// A workspace whose two test actors are root. The door's gate has a
/// test of its own below.
async fn plane() -> (tempfile::TempDir, Plane) {
    let dir = tempfile::tempdir().expect("a tempdir");
    let mut config = glossdb_duck::testing::golden(dir.path()).await.unwrap();
    config.root = vec![agent().id, human().id];
    let plane = Plane::open(config).await.expect("the workspace opens");
    (dir, plane)
}

/// A door opens the workspace, never the engine: a standard actor
/// lands, writes, copies, drops, declares, glosses and reads; the
/// engine's knobs are closed with a reason, in a sequence as the
/// refused statement; a root actor has them.
#[tokio::test(flavor = "multi_thread")]
async fn the_door_opens_the_workspace_and_closes_the_engine() {
    if !extension_present() {
        return;
    }
    let dir = tempfile::tempdir().expect("a tempdir");
    let mut config = glossdb_duck::testing::golden(dir.path()).await.unwrap();
    config.root = vec![human().id];
    let plane = Plane::open(config).await.expect("the workspace opens");
    let agent = plane.channel(agent(), None).await.unwrap();
    agent
        .execute("DECLARE DATASET fin SET (purpose: 'the gate'); USE fin;")
        .await
        .unwrap();
    for (statement, word) in [
        ("SET VARIABLE glossql_actor = 'human'", "SET"),
        ("RESET memory_limit", "RESET"),
        ("PRAGMA enable_profiling", "PRAGMA"),
        ("ATTACH ':memory:' AS other", "ATTACH"),
        ("INSTALL spatial", "INSTALL"),
        ("LOAD spatial", "LOAD"),
        ("CALL ducklake_expire_snapshots('ws')", "CALL"),
        ("IMPORT DATABASE 'nowhere'", "IMPORT DATABASE"),
        (
            "-- a comment first\nEXPORT DATABASE 'nowhere'",
            "EXPORT DATABASE",
        ),
    ] {
        match agent.execute(statement).await {
            Err(SessionError::Closed { statement: s, .. }) => assert_eq!(s, word, "{statement}"),
            other => panic!("{statement}: {other:?}"),
        }
    }
    let text = agent
        .execute("SET VARIABLE glossql_actor = 'human'")
        .await
        .unwrap_err()
        .to_string();
    assert!(
        text.contains("`SET` is closed at this door: the engine's settings"),
        "{text}"
    );
    let csv = dir.path().join("t.csv").display().to_string();
    for statement in [
        "CREATE TABLE fin.t AS SELECT 1 AS x",
        "INSERT INTO fin.t VALUES (2)",
        "UPDATE fin.t SET x = 3 WHERE x = 2",
        "WITH more AS (SELECT 4 AS x) INSERT INTO fin.t SELECT x FROM more",
        &format!("COPY fin.t TO '{csv}'"),
        &format!("CREATE TABLE fin.back AS SELECT * FROM read_csv('{csv}')"),
        "PRAGMA table_info('fin.t')",
        "DESCRIBE SELECT 1 AS x",
        "BEGIN TRANSACTION",
        "ROLLBACK",
        "DROP TABLE fin.back",
        "DROP TABLE fin.t",
    ] {
        agent
            .execute(statement)
            .await
            .unwrap_or_else(|e| panic!("{statement}: {e}"));
    }
    // SPEC §5.2's removal is a standard actor's too: the extension's
    // statement, run on the store's table behind the view
    agent
        .execute(
            "CREATE TABLE fin.orders AS SELECT 1 AS id, 2.5 AS amount;
             GLOSS role ON orders.amount AS $${\"value\": \"measure\"}$$;",
        )
        .await
        .unwrap();
    let count = |outcomes: Vec<Outcome>| match outcomes.as_slice() {
        [Outcome::Rows { batches, .. }] => rows_as_text(batches)[0][0].clone().unwrap(),
        other => panic!("{other:?}"),
    };
    let glossed = agent
        .execute("SELECT count(*) FROM glossary WHERE aspect = 'role'")
        .await
        .unwrap();
    assert_eq!(count(glossed), "1");
    match agent
        .execute("DELETE FROM glossary WHERE aspect = 'role'")
        .await
        .unwrap()
        .as_slice()
    {
        [Outcome::Affected(1)] => {}
        other => panic!("{other:?}"),
    }
    let gone = agent
        .execute("SELECT count(*) FROM glossary WHERE aspect = 'role'")
        .await
        .unwrap();
    assert_eq!(count(gone), "0");
    match agent
        .execute("SELECT 1 AS x; SET VARIABLE glossql_actor = 'human'; SELECT 2 AS y;")
        .await
    {
        Err(SessionError::Sequence {
            index: 2,
            source,
            landed,
            ..
        }) => {
            assert!(matches!(*source, SessionError::Closed { .. }), "{source}");
            assert_eq!(landed.len(), 1);
        }
        other => panic!("{other:?}"),
    }
    let root = plane.channel(human(), Some("fin")).await.unwrap();
    root.execute("SET VARIABLE glossql_actor = 'human'; PRAGMA enable_profiling;")
        .await
        .unwrap();
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
                .execute(agent(), None, "SELECT count(*) FROM aspects")
                .await
                .unwrap(),
        );
        rows[0][0].clone().unwrap()
    }
    let first = Plane::open(glossdb_duck::testing::golden(dir.path()).await.unwrap())
        .await
        .expect("the workspace opens");
    let session = first.channel(agent(), None).await.unwrap();
    session
        .execute(
            "DECLARE DATASET fin SET (purpose: 'reads');
             USE fin;
             DECLARE ASPECT dso WITH $${\"title\": \"DSO\"}$$ AS VIEW;
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
    let kits = text(
        &second
            .execute(agent(), None, "SELECT count(*) FROM kits")
            .await
            .unwrap(),
    );
    assert_eq!(
        kits,
        vec![vec![Some("6".to_string())]],
        "every kit landed once at the first open and stood at the second"
    );
    let next = text(
        &second
            .execute(
                agent(),
                None,
                "SELECT length(comment) FROM duckdb_views() WHERE database_name = 'ws' \
                 AND schema_name = 'main' AND view_name = 'next'",
            )
            .await
            .unwrap(),
    );
    assert_eq!(
        next,
        vec![vec![Some("32".to_string())]],
        "the next view carries its text's hash"
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
