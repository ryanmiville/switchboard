use serde_json::json;

use super::support::Fixture;

#[test]
fn route_appends_a_domain_rule_when_only_the_default_matched() {
    let f = Fixture::new();
    f.rules(json!([]));
    let out = f.json(&["route", "https://docs.github.com/x", "--profile", "Work"]).ok().json();
    assert_eq!(out["action"], "added");
    assert_eq!(out["written"], true);
    assert_eq!(out["after"]["destination"]["profile"], "Profile 1");
    let rules = &f.read_config()["rules"];
    assert_eq!(
        rules[0],
        json!({ "condition": "domain", "value": "docs.github.com", "profile": "Profile 1" })
    );
}

#[test]
fn route_inserts_just_before_the_rule_that_matches_now() {
    let f = Fixture::new();
    f.rules(json!([
        { "condition": "domain", "value": "a.com", "profile": "Default" },
        { "condition": "contains", "value": "github", "profile": "Default" },
    ]));
    let out = f
        .json(&[
            "route",
            "https://github.com/acme",
            "--profile",
            "Profile 1",
            "--match",
            "contains",
            "--value",
            "github.com/acme",
        ])
        .ok()
        .json();
    assert_eq!(out["rule"]["index"], 2);
    let rules = &f.read_config()["rules"];
    assert_eq!(rules[1]["value"], "github.com/acme");
    assert_eq!(rules[2]["value"], "github");
}

#[test]
fn route_updates_a_rule_with_the_same_condition_and_pattern_in_place() {
    let f = Fixture::new();
    f.rules(json!([{ "condition": "domain", "value": "GitHub.com", "profile": "Default" }]));
    let out =
        f.json(&["route", "https://github.com", "--profile", "Profile 3", "--browser", "Chrome"]).ok().json();
    assert_eq!(out["action"], "updated");
    let config = f.read_config();
    assert_eq!(config["rules"].as_array().unwrap().len(), 1);
    assert_eq!(config["rules"][0]["browser"], f.chrome.as_str());
    assert_eq!(config["rules"][0]["profile"], "Profile 3");
}

#[test]
fn an_ambiguous_profile_name_exits_3_with_candidates_and_writes_nothing() {
    let f = Fixture::new();
    f.rules(json!([]));
    let before = f.config_bytes();
    let run = f.json(&["route", "https://x.com", "--browser", "Google Chrome", "--profile", "Work"]);
    assert_eq!(run.status, 3);
    assert_eq!(run.code(), "ambiguous_profile");
    let candidates: Vec<_> =
        run.json()["error"]["candidates"].as_array().unwrap().iter().map(|c| c["profile"].clone()).collect();
    assert_eq!(candidates, [json!("Profile 2"), json!("Profile 3")]);
    assert_eq!(f.config_bytes(), before);
}

#[test]
fn a_directory_identifier_wins_over_a_colliding_display_name() {
    let f = Fixture::new();
    f.rules(json!([]));
    let out =
        f.json(&["route", "https://x.com", "--browser", "Chrome", "--profile", "Profile 2"]).ok().json();
    assert_eq!(out["after"]["destination"]["profileName"], "Work");
}

#[test]
fn the_same_directory_in_two_browsers_is_resolved_in_the_browser_asked_for() {
    let f = Fixture::new();
    f.rules(json!([]));
    let out = f.json(&["route", "https://x.com", "--browser", "Chrome", "--profile", "Default"]).ok().json();
    assert_eq!(out["after"]["destination"]["profileName"], "Chrome Ryan");
    assert_eq!(out["after"]["destination"]["browserName"], "Google Chrome");
}

#[test]
fn route_is_a_no_op_when_the_link_already_opens_there() {
    let f = Fixture::new();
    f.rules(json!([]));
    let before = f.config_bytes();
    let out = f.json(&["route", "https://x.com", "--profile", "Ryan"]).ok().json();
    assert_eq!(out["changed"], false);
    assert_eq!(f.config_bytes(), before);
}

#[test]
fn route_refuses_to_hide_a_later_rule_unless_allowed() {
    let f = Fixture::new();
    f.rules(json!([
        { "condition": "contains", "value": "acme", "profile": "Default" },
        { "condition": "domain", "value": "docs.github.com", "profile": "Default" },
    ]));
    let before = f.config_bytes();
    let args =
        ["route", "https://github.com/acme", "--profile", "Work", "--match", "contains", "--value", "github"];
    let run = f.json(&args);
    assert_eq!(run.status, 1, "{}", run.stdout);
    assert_eq!(run.code(), "would_shadow");
    assert_eq!(run.json()["error"]["candidates"][0]["index"], 3);
    assert_eq!(f.config_bytes(), before);

    let mut allowed = args.to_vec();
    allowed.push("--allow-shadowing");
    let out = f.json(&allowed).ok().json();
    assert_eq!(out["shadowedRules"][0]["value"], "docs.github.com");
}

#[test]
fn a_rule_that_could_never_route_the_link_is_refused() {
    let f = Fixture::new();
    f.rules(json!([{ "condition": "domain", "value": "github.com", "profile": "Default" }]));
    // An exact rule for a link the earlier domain rule already matches goes before it, so it works;
    // a domain rule for a parent domain updates nothing and lands after, so it can't.
    let run = f.json(&["route", "https://github.com", "--profile", "Work", "--match", "exact"]);
    assert_eq!(run.status, 0, "{}", run.stdout);
}

#[test]
fn a_dry_run_reports_the_change_and_writes_nothing() {
    let f = Fixture::new();
    f.rules(json!([]));
    let before = f.config_bytes();
    let out = f.json(&["route", "https://x.com", "--profile", "Work", "--dry-run"]).ok().json();
    assert_eq!(out["changed"], true);
    assert_eq!(out["written"], false);
    assert_eq!(f.config_bytes(), before);
}

#[test]
fn a_stale_revision_exits_5_and_leaves_the_file_alone() {
    let f = Fixture::new();
    f.rules(json!([]));
    let rev = f.json(&["rules", "list"]).ok().json()["revision"].as_str().unwrap().to_owned();
    f.json(&["route", "https://a.com", "--profile", "Work"]).ok();
    let after_first = f.config_bytes();
    let run = f.json(&["route", "https://b.com", "--profile", "Work", "--if-revision", &rev]);
    assert_eq!(run.status, 5);
    assert_eq!(run.code(), "conflict");
    assert_eq!(f.config_bytes(), after_first);
}

#[test]
fn route_leaves_unrelated_legacy_rules_exactly_as_they_were() {
    let f = Fixture::new();
    // A Swift-era file: `routes`, a display-name profile, no browser on the rule.
    f.write_config(
        format!(
            r#"{{"browser":"{}","defaultProfile":"Ryan","routes":[{{"condition":"domain","value":"old.com","profile":"Work"}}]}}"#,
            f.helium
        )
        .as_bytes(),
    );
    f.json(&["route", "https://new.com", "--profile", "Profile 1"]).ok();
    let config = f.read_config();
    assert_eq!(config["defaultProfile"], "Ryan", "the default isn't normalized");
    assert_eq!(config["rules"][0], json!({ "condition": "domain", "value": "old.com", "profile": "Work" }));
    assert_eq!(config["rules"][1]["value"], "new.com");
}
