use serde_json::json;

use super::support::Fixture;

#[test]
fn picker_settings_are_changed_through_the_cli() {
    let f = Fixture::new();
    f.rules(json!([]));
    f.json(&["picker", "shortcut", "Ctrl+Shift+K"]).ok();
    f.json(&["picker", "favorite", "--browser", "Chrome", "--profile", "Profile 3"]).ok();
    f.json(&["picker", "destination", "--browser", "Helium", "--profile", "Work", "--hide"]).ok();
    let picker = &f.read_config()["picker"];
    assert_eq!(picker["shortcut"], "ctrl+shift+k");
    assert_eq!(
        picker["favorites"][0],
        json!({ "browser": f.chrome, "profile": "Profile 3", "name": "Work" })
    );
    let shown: Vec<_> = picker["destinations"]
        .as_array()
        .unwrap()
        .iter()
        .map(|d| d["profile"].as_str().unwrap().to_owned())
        .collect();
    assert_eq!(shown.len(), 5, "every destination but Helium · Work: {shown:?}");
    f.json(&["picker", "show-all"]).ok();
    assert_eq!(f.read_config()["picker"].get("destinations"), None);
    f.json(&["picker", "unfavorite", "--browser", "Chrome", "--profile", "Profile 3"]).ok();
    assert_eq!(f.read_config()["picker"]["favorites"], json!([]));
}

#[test]
fn only_then_adding_sets_an_exact_list_of_destinations() {
    let f = Fixture::new();
    f.rules(json!([]));
    f.json(&["picker", "destination", "--browser", "Helium", "--profile", "Default", "--only"]).ok();
    f.json(&["picker", "destination", "--browser", "Chrome", "--profile", "Profile 1"]).ok();
    assert_eq!(
        f.read_config()["picker"]["destinations"],
        json!([{ "browser": f.helium, "profile": "Default" }, { "browser": f.chrome, "profile": "Profile 1" }])
    );
}
