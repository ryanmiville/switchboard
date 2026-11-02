use serde_json::json;

use super::support::{Fixture, entry};

#[test]
fn history_lists_newest_first_with_urls_redacted_unless_asked() {
    let f = Fixture::new();
    f.rules(json!([]));
    f.history(&[entry("11110000", "https://a.com/old"), entry("22220000", "https://u:p@b.com/new?code=1#x")]);
    let out = f.json(&["history"]).ok().json();
    assert_eq!(out["entries"][0]["id"], "22220000");
    assert_eq!(out["entries"][0]["url"], "https://…@b.com/new?…#…");
    let full = f.json(&["history", "--full-urls", "--limit", "1"]).ok().json();
    assert_eq!(full["entries"].as_array().unwrap().len(), 1);
    assert_eq!(full["entries"][0]["url"], "https://u:p@b.com/new?code=1#x");
}

#[test]
fn explain_and_route_take_the_last_entry_or_an_id_fragment() {
    let f = Fixture::new();
    f.rules(json!([]));
    f.history(&[entry("abcd1234", "https://a.com/x?t=1"), entry("ffff9999", "https://b.com/")]);
    let last = f.json(&["explain", "--last"]).ok().json();
    assert_eq!(last["url"], "https://b.com/");
    assert_eq!(last["history"]["id"], "ffff9999");
    let by_suffix = f.json(&["explain", "--history", "1234"]).ok().json();
    assert_eq!(by_suffix["url"], "https://a.com/x?…");
    f.json(&["route", "--history", "abcd", "--profile", "Work"]).ok();
    assert_eq!(f.read_config()["rules"][0]["value"], "a.com");
}

#[test]
fn an_unknown_history_id_exits_3_with_recent_entries() {
    let f = Fixture::new();
    f.rules(json!([]));
    f.history(&[entry("abcd1234", "https://a.com/")]);
    let run = f.json(&["explain", "--history", "zzzz"]);
    assert_eq!(run.status, 3);
    assert_eq!(run.code(), "history_entry_not_found");
    assert_eq!(run.json()["error"]["candidates"][0]["id"], "abcd1234");
}

#[test]
fn turning_history_off_makes_history_commands_refuse_but_clear_still_works() {
    let f = Fixture::new();
    f.rules(json!([]));
    f.history(&[entry("abcd1234", "https://a.com/")]);
    f.json(&["history", "off"]).ok();
    assert_eq!(f.read_config()["history"], json!({ "enabled": false }));
    let run = f.json(&["explain", "--last"]);
    assert_eq!(run.status, 1);
    assert_eq!(run.code(), "history_disabled");
    let cleared = f.json(&["history", "clear"]).ok().json();
    assert_eq!(cleared["entries"], 1);
    f.json(&["history", "on"]).ok();
    assert_eq!(f.read_config().get("history"), None, "on is the default, so the key goes away");
}
