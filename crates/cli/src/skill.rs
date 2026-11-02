//! The agent skill: a short `SKILL.md` that points agents at `switchboard-rs skill show`, so
//! upgrading Switchboard updates the guide they follow.

use std::fs;
use std::path::PathBuf;

use serde::Serialize;
use switchboard_core::{Candidate, Code, Env, Home, OpError};

/// The routing guide, printed by `skill show`. Compiled in, so it always matches this CLI.
pub const GUIDE: &str = include_str!("guide.md");

const MARKER: &str = "<!-- switchboard-rs-skill: installed by `switchboard-rs skill setup`; `switchboard-rs skill remove` deletes it. -->";

/// The installed `SKILL.md`.
pub fn content() -> String {
    format!(
        "---
name: switchboard-rs
description: Fix which browser and profile links open in, with the switchboard-rs CLI. Use when the user says a link opened in the wrong browser or profile, or asks to send a site to a particular browser profile.
---
{MARKER}

# Switchboard

Before changing how links are routed, run `switchboard-rs skill show` and follow that guide. It ships with the installed Switchboard, so it always matches this version of the CLI.

Never edit Switchboard's config.json by hand; use the CLI.
"
    )
}

#[derive(clap::ValueEnum, Serialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Agent {
    Claude,
    Codex,
    Opencode,
    Pi,
}

impl Agent {
    const ALL: [Agent; 4] = [Agent::Claude, Agent::Codex, Agent::Opencode, Agent::Pi];

    pub fn name(self) -> &'static str {
        match self {
            Agent::Claude => "claude",
            Agent::Codex => "codex",
            Agent::Opencode => "opencode",
            Agent::Pi => "pi",
        }
    }
}

#[derive(Serialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum State {
    Current,
    Outdated,
    Missing,
    /// A skill with this name that setup didn't install. Left alone.
    Foreign,
    Installed,
    Updated,
    Unchanged,
    Removed,
}

impl State {
    pub fn name(self) -> &'static str {
        match self {
            State::Current => "current",
            State::Outdated => "outdated",
            State::Missing => "missing",
            State::Foreign => "foreign",
            State::Installed => "installed",
            State::Updated => "updated",
            State::Unchanged => "unchanged",
            State::Removed => "removed",
        }
    }
}

#[derive(Serialize, Clone, Debug)]
pub struct Item {
    pub agents: Vec<Agent>,
    pub path: String,
    pub status: State,
}

pub struct Installer<'a> {
    pub home: &'a Home,
    pub env: &'a Env,
}

impl Installer<'_> {
    fn dir(&self, var: &str, default: &str) -> PathBuf {
        self.env.var(var).map_or_else(|| self.home.join(default), PathBuf::from)
    }

    /// Agents are found by their configuration folders.
    fn is_present(&self, agent: Agent) -> bool {
        match agent {
            Agent::Claude => self.dir("CLAUDE_CONFIG_DIR", ".claude"),
            Agent::Codex => self.dir("CODEX_HOME", ".codex"),
            Agent::Opencode => self.dir("XDG_CONFIG_HOME", ".config").join("opencode"),
            Agent::Pi => self.home.join(".pi"),
        }
        .exists()
    }

    fn skill_path(&self, agent: Agent) -> PathBuf {
        let root = match agent {
            Agent::Claude => self.dir("CLAUDE_CONFIG_DIR", ".claude"),
            Agent::Codex if self.env.var("CODEX_HOME").is_some() => self.dir("CODEX_HOME", ".codex"),
            Agent::Codex | Agent::Opencode | Agent::Pi => self.home.join(".agents"),
        };
        root.join("skills/switchboard-rs/SKILL.md")
    }

    /// Agents that share a location appear once.
    fn locations(&self, agents: &[Agent]) -> Vec<(Vec<Agent>, PathBuf)> {
        let mut out: Vec<(Vec<Agent>, PathBuf)> = Vec::new();
        for &agent in agents {
            let path = self.skill_path(agent);
            match out.iter_mut().find(|(_, p)| *p == path) {
                Some((list, _)) => list.push(agent),
                None => out.push((vec![agent], path)),
            }
        }
        out
    }

    fn state(path: &std::path::Path) -> State {
        match fs::read_to_string(path) {
            Err(_) => State::Missing,
            Ok(text) if !text.contains("<!-- switchboard-rs-skill") => State::Foreign,
            Ok(text) if text == content() => State::Current,
            Ok(_) => State::Outdated,
        }
    }

    fn item(agents: Vec<Agent>, path: &std::path::Path, status: State) -> Item {
        Item { agents, path: path.to_string_lossy().into_owned(), status }
    }

    /// Detected agents, plus any location that already holds a skill.
    pub fn status(&self, agent: Option<Agent>) -> Vec<Item> {
        let agents = agent.map_or(Agent::ALL.to_vec(), |a| vec![a]);
        self.locations(&agents)
            .into_iter()
            .filter_map(|(list, path)| {
                let present: Vec<Agent> = if agent.is_some() {
                    list.clone()
                } else {
                    list.iter().copied().filter(|a| self.is_present(*a)).collect()
                };
                let state = Self::state(&path);
                (!present.is_empty() || state != State::Missing)
                    .then(|| Self::item(if present.is_empty() { list } else { present }, &path, state))
            })
            .collect()
    }

    pub fn setup(
        &self,
        agent: Option<Agent>,
        dry_run: bool,
    ) -> Result<Vec<Item>, Result<OpError, std::io::Error>> {
        let agents: Vec<Agent> = agent
            .map_or_else(|| Agent::ALL.into_iter().filter(|a| self.is_present(*a)).collect(), |a| vec![a]);
        if agents.is_empty() {
            return Err(Ok(OpError::new(
                Code::AgentNotFound,
                "No supported agent was found. Choose one with --agent.",
            )
            .with(
                Agent::ALL
                    .iter()
                    .map(|a| Candidate { agent: Some(a.name().into()), ..Candidate::default() })
                    .collect(),
            )));
        }
        let mut items = Vec::new();
        for (list, path) in self.locations(&agents) {
            let result = match Self::state(&path) {
                State::Missing => State::Installed,
                State::Outdated => State::Updated,
                State::Foreign => State::Foreign,
                _ => State::Unchanged,
            };
            if !dry_run && matches!(result, State::Installed | State::Updated) {
                if let Some(dir) = path.parent() {
                    fs::create_dir_all(dir).map_err(Err)?;
                }
                fs::write(&path, content()).map_err(Err)?;
            }
            items.push(Self::item(list, &path, result));
        }
        Ok(items)
    }

    /// Removes only skills that setup installed.
    pub fn remove(&self, agent: Option<Agent>, dry_run: bool) -> std::io::Result<Vec<Item>> {
        let agents = agent.map_or(Agent::ALL.to_vec(), |a| vec![a]);
        let mut items = Vec::new();
        for (list, path) in self.locations(&agents) {
            match Self::state(&path) {
                State::Current | State::Outdated => {
                    if !dry_run {
                        fs::remove_file(&path)?;
                        if let Some(dir) = path.parent() {
                            // Only an empty folder goes; anything else in it stays.
                            fs::remove_dir(dir).ok();
                        }
                    }
                    items.push(Self::item(list, &path, State::Removed));
                }
                State::Foreign => items.push(Self::item(list, &path, State::Foreign)),
                _ if agent.is_some() => items.push(Self::item(list, &path, State::Missing)),
                _ => {}
            }
        }
        Ok(items)
    }
}
