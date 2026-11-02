use serde::Serialize;
use switchboard_core::OpError;

use super::{Output, write_failed};
use crate::cli::Skill;
use crate::session::Session;
use crate::skill::{GUIDE, Installer, Item};

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Report {
    items: Vec<Item>,
    #[serde(skip_serializing_if = "Option::is_none")]
    dry_run: Option<bool>,
}

pub fn run(session: &Session<'_>, command: &Skill) -> Result<Output, OpError> {
    let installer = Installer { home: &session.context.home, env: &session.context.env };
    let (items, dry_run) = match command {
        Skill::Show => {
            return Ok(Output::new(&serde_json::json!({ "guide": GUIDE }), GUIDE.to_owned()));
        }
        Skill::Status(a) => (installer.status(a.agent), None),
        Skill::Setup(a) => (
            installer
                .setup(a.agent.agent, a.dry_run)
                .map_err(|e| e.unwrap_or_else(|e| write_failed("The skill couldn't be written.", e)))?,
            Some(a.dry_run),
        ),
        Skill::Remove(a) => (
            installer
                .remove(a.agent.agent, a.dry_run)
                .map_err(|e| write_failed("The skill couldn't be removed.", e))?,
            Some(a.dry_run),
        ),
    };
    let mut text = if items.is_empty() { "No skills found.\n".to_owned() } else { String::new() };
    for item in &items {
        let agents: Vec<&str> = item.agents.iter().map(|a| a.name()).collect();
        text += &format!("{:<10} {}  ({})\n", item.status.name(), item.path, agents.join(", "));
    }
    if dry_run == Some(true) {
        text += "No changes written (dry run).\n";
    }
    Ok(Output::new(&Report { items, dry_run }, text))
}
