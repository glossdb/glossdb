//! The engine's own suite: a workspace opened on a tempdir, the kits
//! declared, statements of the language run through a channel, reads
//! streamed, the summary counted, a review decision stored. Needs the extension
//! beside this checkout (`GLOSSQL_EXTENSION` overrides the path).

use glossdb_duck::{Actor, ActorKind, Config, Outcome, Plane, SessionError, rows_as_text};

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

/// A workspace whose two test actors are root. The interface's gate has a
/// test of its own below.
async fn plane() -> (tempfile::TempDir, Plane) {
    let dir = tempfile::tempdir().expect("a tempdir");
    let mut config = glossdb_duck::testing::golden(dir.path()).await.unwrap();
    config.root = vec![agent().id, human().id];
    let plane = Plane::open(config).await.expect("the workspace opens");
    (dir, plane)
}

/// A interface opens the workspace, never the engine: a standard actor
/// loads, writes, copies, drops, declares, glosses and reads; the
/// engine's knobs are closed with a reason, in a sequence as the
/// refused statement; a root actor has them.
#[tokio::test(flavor = "multi_thread")]
async fn a_standard_actor_uses_the_workspace_and_not_the_engine_settings() {
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
        .execute("SELECT count(*) FROM glossary WHERE property = 'role'")
        .await
        .unwrap();
    assert_eq!(count(glossed), "1");
    match agent
        .execute("DELETE FROM glossary WHERE property = 'role'")
        .await
        .unwrap()
        .as_slice()
    {
        [Outcome::Affected(1)] => {}
        other => panic!("{other:?}"),
    }
    let gone = agent
        .execute("SELECT count(*) FROM glossary WHERE property = 'role'")
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
            loaded,
            ..
        }) => {
            assert!(matches!(*source, SessionError::Closed { .. }), "{source}");
            assert_eq!(loaded.len(), 1);
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
async fn the_language_runs_through_a_channel_and_the_glossary_reads_back() {
    let (_dir, plane) = plane().await;
    assert!(plane.datasets().await.unwrap().is_empty());
    assert_eq!(plane.summary_counts().await.unwrap().human_writings, 0);

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
        .execute("SELECT subject, property, value FROM GLOSSARY(orders.amount)")
        .await
        .unwrap();
    let rows = text(&read);
    assert!(
        rows.iter().any(|r| r[1].as_deref() == Some("role")),
        "{rows:?}"
    );

    // A page is cut one row past the cap; a catalog read never is.
    let page = bound.query_page("SELECT * FROM fin.orders").await.unwrap();
    assert_eq!(page.cap, 200);
    assert!(!page.catalog);
    let whole = bound.query_page("SELECT * FROM glossary").await.unwrap();
    assert_eq!(whole.cap, usize::MAX);
    assert!(whole.catalog);
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
            loaded,
            ..
        }) => {
            assert_eq!((index, total, loaded.len()), (2, 2, 1));
        }
        other => panic!("{other:?}"),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_review_decision_is_stored_as_the_person_and_counted() {
    let (_dir, plane) = plane().await;
    plane
        .execute(
            agent(),
            None,
            "DECLARE DATASET fin SET (purpose: 'decisions')",
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
    let before = plane.summary_counts().await.unwrap();
    assert_eq!(before.human_writings, 0);

    let session = plane.channel(human(), Some("fin")).await.unwrap();
    glossdb_duck::decisions::store(
        &session,
        glossdb_duck::decisions::Decision {
            subject: "orders.id",
            property: "meaning",
            dimension: "scope",
            key: "k1",
            assumption: "ids are contiguous",
            stance: "confirmed",
            note: None,
        },
    )
    .await
    .unwrap();

    // The decision is the person's own annotation, and the summary
    // counts it.
    let stored = text(
        &session
            .execute(
                "SELECT actor_kind, actor_id, json_extract_string(body, '$.decisions[0].key'), \
                 json_extract_string(body, '$.decisions[0].stance') \
                 FROM glossary WHERE property = 'review_decision'",
            )
            .await
            .unwrap(),
    );
    let cell = |s: &str| Some(s.to_string());
    assert_eq!(
        stored,
        vec![vec![
            cell("human"),
            cell("test:human"),
            cell("k1"),
            cell("confirmed")
        ]]
    );
    let after = plane.summary_counts().await.unwrap();
    assert_eq!(after.human_writings, 1);
    assert!(after.latest_human_at.is_some());
    assert_eq!(after.decisions_open, 0);
}

/// A second open of a workspace declares nothing twice and its derived
/// reads hold; a kit whose text changed runs again at the next open,
/// over the views the last one left in main and a dataset's metric view.
#[tokio::test(flavor = "multi_thread")]
async fn a_second_open_changes_nothing_and_a_changed_kit_runs_again() {
    let dir = tempfile::tempdir().expect("a tempdir");
    async fn count(plane: &Plane) -> String {
        let rows = text(
            &plane
                .execute(agent(), None, "SELECT count(*) FROM properties")
                .await
                .unwrap(),
        );
        rows[0][0].clone().unwrap()
    }
    let config = glossdb_duck::testing::golden(dir.path()).await.unwrap();
    let first = Plane::open(config.clone())
        .await
        .expect("the workspace opens");
    let session = first.channel(agent(), None).await.unwrap();
    session
        .execute(
            "DECLARE DATASET fin SET (purpose: 'reads');
             USE fin;
             DECLARE PROPERTY dso WITH $${\"title\": \"DSO\"}$$ AS VIEW;
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
            .execute(
                agent(),
                None,
                "SELECT count(*) > 0 AND count(*) = count(DISTINCT name) FROM kits",
            )
            .await
            .unwrap(),
    );
    assert_eq!(
        kits,
        vec![vec![Some("true".to_string())]],
        "every kit ran once at the first open and was current at the second"
    );
    let next = text(
        &second
            .execute(
                agent(),
                None,
                "SELECT count(*) FROM duckdb_views() WHERE database_name = 'ws' \
                 AND schema_name = 'main' AND view_name = 'next'",
            )
            .await
            .unwrap(),
    );
    assert_eq!(
        next,
        vec![vec![Some("1".to_string())]],
        "the goals kit declared the next view"
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
    drop(second);

    // every kit as it is, the server's own kits each one comment longer
    let kits = tempfile::tempdir().unwrap();
    let mut changed = config.clone();
    changed.kits = config
        .kits
        .iter()
        .map(|kit| {
            let name = kit.parent().and_then(|p| p.file_name()).unwrap();
            let mut text = std::fs::read_to_string(kit).unwrap();
            if ["core", "views", "harmonise", "goals"]
                .iter()
                .any(|k| name == *k)
            {
                text.push_str("\n-- the same kit, once more\n");
            }
            let folder = kits.path().join(name);
            std::fs::create_dir_all(&folder).unwrap();
            let copy = folder.join("kit.sql");
            std::fs::write(&copy, text).unwrap();
            copy
        })
        .collect();
    // the open on a task of its own: one that never returns holds its worker,
    // never the clock that ends the test
    let third = tokio::time::timeout(
        std::time::Duration::from_secs(120),
        tokio::spawn(Plane::open(changed)),
    )
    .await
    .expect("the open completes within two minutes")
    .unwrap()
    .expect("the workspace reopens");
    let core = text(
        &third
            .execute(
                agent(),
                None,
                "SELECT count(DISTINCT hash) FROM kits_history WHERE name = 'core'",
            )
            .await
            .unwrap(),
    );
    assert_eq!(
        core,
        vec![vec![Some("2".to_string())]],
        "the core kit ran again"
    );
}

/// Two sessions write to one workspace at the same time: each
/// annotation lands exactly once, each in a snapshot of its own, and a
/// statement refused while the other session writes returns its own
/// code, not a lost race.
#[tokio::test(flavor = "multi_thread")]
async fn two_writers_at_once_each_land_once_and_a_refusal_keeps_its_code() {
    const EACH: usize = 12;
    let (_dir, plane) = plane().await;
    let columns: Vec<String> = (0..2 * EACH).map(|i| format!("{i} AS c{i}")).collect();
    plane
        .execute(
            agent(),
            None,
            &format!(
                "DECLARE DATASET fin SET (purpose: 'two writers');
                 CREATE TABLE fin.wide AS SELECT {};
                 DECLARE PROPERTY remark WITH $${{\"type\": \"object\"}}$$ AS FACT ON COLUMN;
                 DECLARE PROPERTY raw WITH $${{\"type\": \"integer\"}}$$ AS MEASUREMENT ON TABLE;",
                columns.join(", ")
            ),
        )
        .await
        .unwrap();
    let glosses = |from: usize| -> String {
        (from..from + EACH)
            .map(|i| format!("GLOSS remark ON wide.c{i} AS $${{\"n\": {i}}}$$;"))
            .collect::<Vec<_>>()
            .join("\n")
    };
    let first = plane.channel(agent(), Some("fin")).await.unwrap();
    let second = plane.channel(human(), Some("fin")).await.unwrap();
    let (ones, twos) = (glosses(0), glosses(EACH));
    let (one, two) = tokio::join!(first.execute(&ones), async {
        let refused = second
            .execute(
                "DECLARE FUNCTION raw FOR fin AS $$ SELECT count(*) AS n FROM main.glossary $$ RETURNS raw;",
            )
            .await;
        (refused, second.execute(&twos).await)
    });
    assert_eq!(one.unwrap().len(), EACH);
    let (refused, written) = two;
    assert_eq!(written.unwrap().len(), EACH);
    assert_eq!(refused.unwrap_err().code(), Some("untracked_read"));

    let read = first
        .execute(
            "SELECT count(*), count(DISTINCT subject), count(DISTINCT begin_snapshot)
             FROM glossary_history WHERE property = 'remark'",
        )
        .await
        .unwrap();
    let total = (2 * EACH).to_string();
    assert_eq!(
        text(&read),
        vec![vec![Some(total.clone()), Some(total.clone()), Some(total)]]
    );
}

/// This repository's kits' suites, `kits/<kit>/kit.test`, on the
/// engine, each on a lake of its own and on a thread of its own: a
/// suite loads its kits itself, which is what it tests, so the wait is
/// the slowest suite's.
#[test]
fn the_kits_suites_pass() {
    let kits = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../kits");
    let mut suites: Vec<_> = std::fs::read_dir(&kits)
        .expect("the kits directory")
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path().join("kit.test"))
        .filter(|suite| suite.exists())
        .collect();
    suites.sort();
    assert!(!suites.is_empty(), "no suite under {}", kits.display());
    let failures: Vec<String> = std::thread::scope(|scope| {
        let runs: Vec<_> = suites
            .iter()
            .map(|suite| {
                scope.spawn(move || {
                    let dir = tempfile::tempdir().expect("a tempdir");
                    let records = glossdb_duck::sqllogic::run_suite(suite, dir.path())?;
                    eprintln!("{}: {records} records", suite.display());
                    Ok::<(), String>(())
                })
            })
            .collect();
        runs.into_iter()
            .filter_map(|run| run.join().expect("a suite's thread").err())
            .collect()
    });
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
