use serde_json::json;

use super::support::Fixture;

#[test]
fn usage_errors_exit_2_and_with_json_print_an_error_object() {
    let f = Fixture::new();
    let run = f.json(&["route", "https://a.com"]);
    assert_eq!(run.status, 2);
    assert_eq!(run.code(), "invalid_argument");
    assert!(run.json()["error"]["message"].as_str().unwrap().contains("--profile"));
    let plain = f.run(&["nonsense"]);
    assert_eq!(plain.status, 2);
    assert!(plain.stderr.contains("nonsense"));
}

#[test]
fn config_prints_the_whole_file_with_its_revision() {
    let f = Fixture::new();
    f.rules(json!([{ "condition": "domain", "value": "a.com", "profile": "Default" }]));
    let out = f.json(&["config"]).ok().json();
    assert_eq!(out["config"]["rules"][0]["value"], "a.com");
    assert_eq!(out["exists"], true);
}

#[test]
fn a_typo_in_the_config_is_reported_with_its_name() {
    let f = Fixture::new();
    f.write_config(br#"{"browser":"b","defaultProfile":"Default","rulez":[]}"#);
    let run = f.json(&["doctor"]).ok().json();
    assert_eq!(run["ok"], false);
    assert!(run["config"]["error"].as_str().unwrap().contains("rulez"));
}

#[test]
fn doctor_reports_missing_profiles_and_unreachable_rules() {
    let f = Fixture::new();
    f.rules(json!([
        { "condition": "domain", "value": "github.com", "profile": "Default" },
        { "condition": "domain", "value": "docs.github.com", "profile": "Nobody" },
    ]));
    let out = f.json(&["doctor"]).ok().json();
    assert_eq!(out["ok"], false);
    let problems: Vec<_> =
        out["rules"].as_array().unwrap().iter().map(|p| p["problem"].as_str().unwrap().to_owned()).collect();
    assert_eq!(problems, ["profile_missing", "unreachable"]);
    assert_eq!(out["browsers"][0]["profileCount"], 2);

    let g = Fixture::new();
    g.rules(json!([]));
    assert_eq!(g.json(&["doctor"]).ok().json()["ok"], true);
}

#[test]
fn profiles_lists_each_browser_with_its_directories_and_names() {
    let f = Fixture::new();
    f.rules(json!([]));
    let out = f.json(&["profiles"]).ok().json();
    let names: Vec<_> =
        out["browsers"].as_array().unwrap().iter().map(|b| b["name"].as_str().unwrap().to_owned()).collect();
    assert_eq!(names, ["Google Chrome", "Helium"]);
    assert_eq!(out["browsers"][1]["isDefault"], true);
    assert_eq!(out["browsers"][1]["profiles"][1], json!({ "profile": "Profile 1", "profileName": "Work" }));
    let one = f.json(&["profiles", "--browser", "chrome"]).ok().json();
    assert_eq!(one["browsers"].as_array().unwrap().len(), 1);
    let none = f.json(&["profiles", "--browser", "Firefox"]);
    assert_eq!(none.status, 3);
    assert_eq!(none.code(), "browser_not_found");
}
