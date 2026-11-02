use serde_json::json;

use super::support::Fixture;

#[test]
fn explain_names_the_first_matching_rule_and_the_rules_it_hides() {
    let f = Fixture::new();
    f.rules(json!([
        { "condition": "domain", "value": "example.com", "profile": "Default" },
        { "condition": "domain", "value": "github.com", "profile": "Profile 1" },
        { "condition": "contains", "value": "acme", "profile": "Default" },
    ]));
    let out = f.json(&["explain", "https://github.com/acme/api"]).ok().json();
    assert_eq!(out["matchedRule"]["index"], 2);
    assert_eq!(out["destination"]["profile"], "Profile 1");
    assert_eq!(out["destination"]["profileName"], "Work");
    assert_eq!(out["destination"]["browserName"], "Helium");
    assert_eq!(out["profileStatus"], "ok");
    assert_eq!(out["alsoMatches"][0]["index"], 3);

    let text = f.run(&["explain", "https://github.com/acme/api"]).ok().stdout;
    assert!(text.contains("Rule 2 matched: domain github.com"), "{text}");
    assert!(text.contains("Helium · Work (Profile 1)"), "{text}");
}

#[test]
fn an_unmatched_link_uses_the_default_destination() {
    let f = Fixture::new();
    f.rules(json!([]));
    let out = f.json(&["explain", "https://example.com"]).ok().json();
    assert_eq!(out["matchedRule"], serde_json::Value::Null);
    assert_eq!(out["destination"]["profileName"], "Ryan");
}

#[test]
fn a_rule_whose_profile_is_gone_reports_it_as_missing() {
    let f = Fixture::new();
    f.rules(json!([{ "condition": "domain", "value": "a.com", "profile": "Profile 9" }]));
    let out = f.json(&["explain", "https://a.com"]).ok().json();
    assert_eq!(out["profileStatus"], "missing");
}

#[test]
fn a_chrome_rule_with_a_helium_default_resolves_its_profile_in_chrome() {
    let f = Fixture::new();
    f.rules(json!([
        { "condition": "domain", "value": "work.com", "profile": "Default", "browser": f.chrome },
        { "condition": "domain", "value": "home.com", "profile": "Default" },
    ]));
    let work = f.json(&["explain", "https://work.com"]).ok().json();
    assert_eq!(work["destination"]["profileName"], "Chrome Ryan");
    let home = f.json(&["explain", "https://home.com"]).ok().json();
    assert_eq!(home["destination"]["profileName"], "Ryan", "a rule without a browser inherits Helium");
}

#[test]
fn a_link_that_is_not_a_complete_url_is_a_usage_error() {
    let f = Fixture::new();
    let run = f.json(&["explain", "github.com"]);
    assert_eq!(run.status, 2);
    assert_eq!(run.code(), "invalid_argument");
}
