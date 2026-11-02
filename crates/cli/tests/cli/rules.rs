use serde_json::json;

use super::support::{Fixture, entry};

#[test]
fn rules_list_shows_inheritance_problems_and_hidden_rules() {
    let f = Fixture::new();
    f.rules(json!([
        { "condition": "domain", "value": "github.com", "profile": "Default" },
        { "condition": "domain", "value": "docs.github.com", "profile": "Profile 2", "browser": f.chrome },
        { "condition": "contains", "value": "x", "profile": "Nobody" },
    ]));
    let out = f.json(&["rules", "list"]).ok().json();
    let rules = out["rules"].as_array().unwrap();
    assert_eq!(rules[0]["browser"], serde_json::Value::Null);
    assert_eq!(rules[0]["destination"]["browserName"], "Helium");
    assert_eq!(rules[1]["shadowedBy"], 1);
    assert_eq!(rules[1]["destination"]["profileName"], "Work");
    assert_eq!(rules[2]["profileStatus"], "missing");
    assert_eq!(out["default"]["destination"]["profileName"], "Ryan");
    assert_eq!(out["revision"].as_str().unwrap().len(), 64);

    let text = f.run(&["rules", "list"]).ok().stdout;
    assert!(text.contains("(default browser)"), "{text}");
    assert!(text.contains("Never matches: rule 1"), "{text}");
}

#[test]
fn changing_a_rules_browser_requires_a_profile() {
    let f = Fixture::new();
    f.rules(json!([{ "condition": "domain", "value": "a.com", "profile": "Default" }]));
    let run = f.json(&["rules", "update", "1", "--browser", "Chrome"]);
    assert_eq!(run.status, 2);
    let out = f.json(&["rules", "update", "1", "--browser", "Chrome", "--profile", "Profile 3"]).ok().json();
    assert_eq!(out["rule"]["destination"]["browserName"], "Google Chrome");
    assert_eq!(out["previous"]["destination"]["browserName"], "Helium");
}

#[test]
fn moving_and_removing_report_recent_links_that_would_open_elsewhere() {
    let f = Fixture::new();
    f.rules(json!([
        { "condition": "domain", "value": "a.com", "profile": "Profile 1" },
        { "condition": "contains", "value": "a.com/x", "profile": "Default" },
    ]));
    f.history(&[entry("aaaa0001", "https://a.com/x?token=secret")]);
    let out = f.json(&["rules", "remove", "1", "--dry-run"]).ok().json();
    assert_eq!(out["historyChecked"], true);
    assert_eq!(out["historyChanges"][0]["url"], "https://a.com/x?…", "history URLs are redacted");
    assert_eq!(out["historyChanges"][0]["after"]["rule"]["index"], 1);

    let moved = f.json(&["rules", "move", "2", "1"]).ok().json();
    assert_eq!(moved["action"], "moved");
    assert_eq!(f.read_config()["rules"][0]["value"], "a.com/x");
}

#[test]
fn a_missing_rule_exits_3_with_the_rules_listed() {
    let f = Fixture::new();
    f.rules(json!([{ "condition": "domain", "value": "a.com", "profile": "Default" }]));
    let run = f.json(&["rules", "remove", "4"]);
    assert_eq!(run.status, 3);
    assert_eq!(run.code(), "rule_not_found");
    assert_eq!(run.json()["error"]["candidates"][0]["value"], "a.com");
}

#[test]
fn the_default_browser_cant_change_while_rules_inherit_it() {
    let f = Fixture::new();
    f.rules(json!([{ "condition": "domain", "value": "a.com", "profile": "Profile 1" }]));
    let run = f.json(&["default", "--browser", "Chrome", "--profile", "Default"]);
    assert_eq!(run.status, 3);
    assert_eq!(run.code(), "inheriting_rules");
    let suggestion = run.json()["error"]["candidates"][0]["suggestion"].as_str().unwrap().to_owned();
    assert!(
        suggestion.contains("rules update 1 --browser") && suggestion.contains("--profile 'Profile 1'"),
        "{suggestion}"
    );

    let g = Fixture::new();
    g.rules(json!([]));
    let out = g.json(&["default", "--browser", "Chrome", "--profile", "Chrome Ryan"]).ok().json();
    assert_eq!(out["destination"]["browserName"], "Google Chrome");
    assert_eq!(g.read_config()["defaultProfile"], "Default");
}

#[test]
fn a_malformed_config_exits_4_and_is_never_replaced() {
    let f = Fixture::new();
    f.write_config(b"{\"browser\": ");
    let run = f.json(&["route", "https://a.com", "--profile", "Work"]);
    assert_eq!(run.status, 4);
    assert_eq!(run.code(), "config_invalid");
    assert_eq!(f.config_bytes(), b"{\"browser\": ");
}

#[test]
fn with_no_config_the_cli_says_no_default_browser_is_chosen() {
    let f = Fixture::new();
    let text = f.run(&["rules", "list"]).ok().stdout;
    assert!(text.contains("No default browser is chosen"), "{text}");
    let out = f.json(&["default", "--browser", "Helium", "--profile", "Work"]).ok().json();
    assert_eq!(out["destination"]["profile"], "Profile 1");
    assert_eq!(f.read_config()["browser"], f.helium.as_str());
}
