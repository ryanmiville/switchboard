use super::support::Fixture;

#[test]
fn skill_setup_installs_for_detected_agents_and_leaves_foreign_skills_alone() {
    let f = Fixture::new();
    std::fs::create_dir_all(f.home.join(".claude")).unwrap();
    std::fs::create_dir_all(f.home.join(".codex")).unwrap();
    let foreign = f.home.join(".agents/skills/switchboard-rs/SKILL.md");
    std::fs::create_dir_all(foreign.parent().unwrap()).unwrap();
    std::fs::write(&foreign, "mine").unwrap();

    let out = f.json(&["skill", "setup"]).ok().json();
    let statuses: Vec<_> =
        out["items"].as_array().unwrap().iter().map(|i| i["status"].as_str().unwrap().to_owned()).collect();
    assert_eq!(statuses, ["installed", "foreign"]);
    assert!(f.home.join(".claude/skills/switchboard-rs/SKILL.md").exists());
    assert_eq!(std::fs::read_to_string(&foreign).unwrap(), "mine");

    let again = f.json(&["skill", "setup"]).ok().json();
    assert_eq!(again["items"][0]["status"], "unchanged");
    let removed = f.json(&["skill", "remove"]).ok().json();
    assert_eq!(removed["items"][0]["status"], "removed");
    assert!(!f.home.join(".claude/skills/switchboard-rs").exists());
    assert_eq!(std::fs::read_to_string(&foreign).unwrap(), "mine");
}

#[test]
fn skill_setup_with_no_agent_found_exits_3() {
    let f = Fixture::new();
    let run = f.json(&["skill", "setup"]);
    assert_eq!(run.status, 3);
    assert_eq!(run.code(), "agent_not_found");
}

#[test]
fn skill_show_prints_the_guide() {
    let f = Fixture::new();
    assert!(f.run(&["skill", "show"]).ok().stdout.starts_with("# Switchboard routing guide"));
}
