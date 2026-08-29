//! T-203..T-208 query behavior against the seeded fixture, including the
//! compliance-critical exclusions (scope filtering, private/local-only
//! murmurs, local_alias / access_token never surfaced).

mod common;

use ansible_mcp::{db, grant, queries};

fn setup(tag: &str, narrow: bool) -> (common::Fixture, rusqlite::Connection, grant::Grant) {
    let fixture = common::seeded_fixture(tag);
    if narrow {
        fixture.write_narrow_grant();
    } else {
        fixture.write_default_grant();
    }
    let conn = db::open(fixture.data_dir()).unwrap();
    let grant = grant::load(fixture.data_dir()).unwrap();
    (fixture, conn, grant)
}

#[test]
fn list_boards_full_scope_includes_provenance() {
    let (_fixture, conn, grant) = setup("boards_full", false);
    let value = queries::list_boards(&conn, &grant).unwrap();
    let boards = value["boards"].as_array().unwrap();
    // Deleted board excluded.
    assert_eq!(boards.len(), 2);
    let dev = boards.iter().find(|b| b["board_id"] == "b-dev").unwrap();
    assert_eq!(dev["origin_host"], "Genesis Host");
    assert_eq!(dev["host_compliance"], "unknown"); // forum_hosts has no level yet
    let priv_board = boards.iter().find(|b| b["board_id"] == "b-priv").unwrap();
    assert_eq!(priv_board["origin_host"], "Peer Node");
    assert_eq!(priv_board["host_compliance"], "compatible");
}

#[test]
fn deliberation_exports_are_explicit_expiring_and_board_scoped() {
    let fixture = common::seeded_fixture("queries_deliberation_exports");
    fixture.write_narrow_grant();
    let conn = rusqlite::Connection::open(fixture.db_path()).unwrap();
    let grant = ansible_mcp::grant::load(fixture.data_dir()).unwrap();

    let listed = queries::list_deliberations(&conn, &grant).unwrap();
    assert_eq!(listed["deliberations"].as_array().unwrap().len(), 1);
    assert_eq!(listed["deliberations"][0]["deliberation_id"], "d-dev");

    let report = queries::get_deliberation_report(&conn, &grant, "d-dev").unwrap();
    assert_eq!(report["report"]["participant_count"], 3);

    let rows = queries::list_deliberation_responses(&conn, &grant, "d-dev").unwrap();
    let serialized = rows.to_string();
    assert!(serialized.contains("export-person-1"));
    assert!(!serialized.contains("did:"));

    assert!(queries::get_deliberation_report(&conn, &grant, "d-private").is_err());
}

#[test]
fn narrow_scope_hides_other_boards_everywhere() {
    let (_fixture, conn, grant) = setup("boards_narrow", true);

    let value = queries::list_boards(&conn, &grant).unwrap();
    let boards = value["boards"].as_array().unwrap();
    assert_eq!(boards.len(), 1);
    assert_eq!(boards[0]["board_id"], "b-dev");

    // list_threads on the out-of-scope board reads as not-found.
    let err = queries::list_threads(&conn, &grant, "b-priv", None, None).unwrap_err();
    assert!(matches!(err, queries::QueryError::NotFound(_)));

    // get_thread on a thread in the out-of-scope board reads as not-found.
    let err = queries::get_thread(&conn, &grant, "t-secret", None, None).unwrap_err();
    assert!(matches!(err, queries::QueryError::NotFound(_)));

    // search never returns rows from the out-of-scope board.
    let value = queries::search_content(&conn, &grant, "zebra").unwrap();
    let results = serde_json::to_string(&value).unwrap();
    assert!(!results.contains("Secret zebra cabal"));
    assert!(!results.contains("b-priv"));
    assert!(results.contains("p-1"));
}

#[test]
fn get_thread_returns_envelope_and_tree() {
    let (_fixture, conn, grant) = setup("thread_env", false);
    let value = queries::get_thread(&conn, &grant, "t-1", None, None).unwrap();
    assert_eq!(value["board_id"], "b-dev");
    assert_eq!(value["origin_host"], "Genesis Host");
    let posts = value["posts"].as_array().unwrap();
    // Deleted post excluded.
    assert_eq!(posts.len(), 2);
    let first = &posts[0];
    assert_eq!(first["author_did"], "did:key:alice");
    assert_eq!(first["author_display"], "Alice A.");
    assert_eq!(first["signature_verified"], true);
    assert_eq!(first["host_compliance"], "unknown");
    assert_eq!(first["content"]["post_id"], "p-1");
    let reply = &posts[1];
    assert_eq!(reply["content"]["parent_post_id"], "p-1");
    assert_eq!(reply["signature_verified"], false);
}

#[test]
fn thread_pagination_cursor_walks_all_posts() {
    let (_fixture, conn, grant) = setup("thread_page", false);
    let page1 = queries::get_thread(&conn, &grant, "t-1", None, Some(1)).unwrap();
    assert_eq!(page1["posts"].as_array().unwrap().len(), 1);
    let cursor = page1["next_cursor"].as_str().unwrap().to_string();
    let page2 = queries::get_thread(&conn, &grant, "t-1", Some(&cursor), Some(1)).unwrap();
    let posts2 = page2["posts"].as_array().unwrap();
    assert_eq!(posts2.len(), 1);
    assert_ne!(
        page1["posts"][0]["content"]["post_id"],
        posts2[0]["content"]["post_id"]
    );
}

#[test]
fn murmur_privacy_rules() {
    let (_fixture, conn, grant) = setup("murmur_privacy", false);
    let value = queries::get_murmurs(&conn, &grant, None, None).unwrap();
    let serialized = serde_json::to_string(&value).unwrap();
    // Own private content is shareable with the user's own AI client.
    assert!(serialized.contains("m-own-private"));
    // Other authors' public murmur is included.
    assert!(serialized.contains("m-alice-public"));
    // Other authors' private / local-only content must never leak.
    assert!(!serialized.contains("must never leak"));
    assert!(!serialized.contains("m-alice-private"));
    assert!(!serialized.contains("m-alice-localonly"));
}

#[test]
fn murmurs_denied_when_scope_off() {
    let (_fixture, conn, grant) = setup("murmur_scope_off", true);
    assert!(matches!(
        queries::get_murmurs(&conn, &grant, None, None).unwrap_err(),
        queries::QueryError::ScopeDisabled("include_murmurs")
    ));
    // Search with murmur scope off must not surface murmurs either.
    let value = queries::search_content(&conn, &grant, "murmur").unwrap();
    assert!(
        !serde_json::to_string(&value)
            .unwrap()
            .contains("m-alice-public")
    );
}

#[test]
fn follow_feed_derives_from_accepted_outbound_edges() {
    let (_fixture, conn, grant) = setup("follow_feed", false);
    let value = queries::get_follow_feed(&conn, &grant, None, None).unwrap();
    let serialized = serde_json::to_string(&value).unwrap();
    // Alice is followed (accepted) → her posts appear.
    assert!(serialized.contains("p-1"));
    // b-dev is followed (accepted) → Bob's post in it appears.
    assert!(serialized.contains("p-3"));
    // b-priv follow is only 'pending' → its posts must not appear.
    assert!(!serialized.contains("p-secret"));
}

#[test]
fn follow_feed_respects_board_scope_even_for_followed_authors() {
    let fixture = common::seeded_fixture("follow_feed_scope");
    // Narrow grant but with follow feed enabled.
    fixture.write_grant(
        r#"{
            "grant_id": "narrow-feed",
            "created_at": "2026-07-01T00:00:00Z",
            "expires_at": "2999-01-01T00:00:00Z",
            "local_author_dids": ["did:key:local"],
            "scopes": { "boards": ["b-dev"], "include_follow_feed": true }
        }"#,
    );
    let conn = db::open(fixture.data_dir()).unwrap();
    let grant = grant::load(fixture.data_dir()).unwrap();
    // Make the b-priv follow accepted so only the grant scope excludes it.
    drop(conn);
    let rw = rusqlite::Connection::open(fixture.db_path()).unwrap();
    rw.execute(
        "UPDATE follow_edges SET status = 'accepted' WHERE follow_id = 'f-3'",
        [],
    )
    .unwrap();
    drop(rw);
    let conn = db::open(fixture.data_dir()).unwrap();
    let value = queries::get_follow_feed(&conn, &grant, None, None).unwrap();
    assert!(!serde_json::to_string(&value).unwrap().contains("p-secret"));
}

#[test]
fn get_author_omits_local_alias() {
    let (_fixture, conn, _grant) = setup("author", false);
    let value = queries::get_author(&conn, "did:key:alice").unwrap();
    assert_eq!(value["display_name"], "Alice A.");
    assert_eq!(value["reputation_tier"], "verified_human");
    assert!(
        !serde_json::to_string(&value)
            .unwrap()
            .contains("secret nickname")
    );
}

#[test]
fn search_escapes_like_metacharacters() {
    let (_fixture, conn, grant) = setup("search_escape", false);
    // '%' as a literal must not match everything.
    let value = queries::search_content(&conn, &grant, "%").unwrap();
    assert_eq!(value["results"].as_array().unwrap().len(), 0);
}

#[test]
fn nothing_ever_serializes_the_remote_node_token() {
    let (_fixture, conn, grant) = setup("token_leak", false);
    for value in [
        queries::list_boards(&conn, &grant).unwrap(),
        queries::get_thread(&conn, &grant, "t-1", None, None).unwrap(),
        queries::search_content(&conn, &grant, "zebra").unwrap(),
        queries::get_follow_feed(&conn, &grant, None, None).unwrap(),
    ] {
        assert!(
            !serde_json::to_string(&value)
                .unwrap()
                .contains("SECRET-TOKEN")
        );
    }
}
