//! The command line, as clap definitions. Behaviour lives in `commands`.

use clap::{Args, Parser, Subcommand, ValueEnum};
use switchboard_core::Condition;

const ABOUT: &str = "Inspect and change how Switchboard routes links.";
const LONG_ABOUT: &str = "Inspect and change how Switchboard routes links.

Reads and writes the same configuration file as the app, whether or not the app is running. It never \
opens links. Add --json to any command for one JSON object on stdout, including errors.

Exit codes: 0 success, 1 failed, 2 invalid command line, 3 not found or ambiguous (nothing changed; \
candidates are listed), 4 the configuration can't be read or is invalid, 5 the configuration changed \
since the given or loaded revision.

Agents: run `switchboard-rs skill show` for the workflow.";

#[derive(Parser, Debug)]
#[command(name = "switchboard-rs", version, about = ABOUT, long_about = LONG_ABOUT)]
pub struct Cli {
    #[command(flatten)]
    pub global: Global,
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Args, Debug, Clone)]
pub struct Global {
    /// Print one JSON object on stdout, including errors.
    #[arg(long, global = true)]
    pub json: bool,
    /// The configuration file. Defaults to $SWITCHBOARD_RS_CONFIG, then
    /// ~/.config/switchboard-rs/config.json.
    #[arg(long, global = true, value_name = "PATH")]
    pub config: Option<String>,
    /// The history file. Defaults to $SWITCHBOARD_RS_HISTORY, then
    /// ~/.local/state/switchboard-rs/history.jsonl.
    #[arg(long = "history-file", global = true, value_name = "PATH")]
    pub history_file: Option<String>,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Show how a URL routes with the current rules, without opening it.
    Explain(Explain),
    /// Make a URL open in a browser profile by adding or updating one rule.
    ///
    /// If the URL already opens there, nothing changes. A rule with the same match and pattern is
    /// updated in place; otherwise the new rule goes immediately before the rule that matches the
    /// URL now, or last if only the default matched. The change is checked with the router before
    /// it is written, and refused if it would stop a later rule from ever matching.
    Route(Route),
    /// List and change routing rules by position.
    ///
    /// Rules are numbered from 1 in the order they are checked; the first match wins. Positions
    /// shift when rules change, so pass --if-revision from the listing to make sure they haven't.
    #[command(subcommand)]
    Rules(Rules),
    /// Show or change the destination for links that match no rule.
    ///
    /// Changing the default browser needs --profile, and is refused (exit 3) while rules inherit
    /// the default browser: their profiles were chosen in the old browser. Give those rules an
    /// explicit browser with `rules update` first.
    Default(Default),
    /// List installed, supported Chromium browsers and their profiles.
    Profiles(Profiles),
    /// List, clear, or turn on and off the history of links Switchboard opened.
    ///
    /// URLs are shown without query strings or fragments, which can carry sign-in tokens. Pass an
    /// entry to `explain` or `route` with --history <id> or --last instead of copying its URL.
    History(History),
    /// Show and change the Quick Switch picker: its shortcut, favorites, and destinations.
    #[command(subcommand)]
    Picker(Picker),
    /// Show the whole configuration, its path, and its revision.
    Config,
    /// Check the configuration, browsers, profiles, and history. Changes nothing.
    Doctor,
    /// Install and manage the agent skill that teaches this workflow.
    #[command(subcommand)]
    Skill(Skill),
}

#[derive(Args, Debug, Clone)]
#[group(id = "link", required = true, multiple = false)]
pub struct Target {
    /// A complete URL, such as https://github.com/acme/api.
    pub url: Option<String>,
    /// Use a history entry: its ID, or four or more characters from its start or end.
    #[arg(long, value_name = "ID")]
    pub history: Option<String>,
    /// Use the most recent history entry.
    #[arg(long)]
    pub last: bool,
}

/// Which link a command is about.
#[derive(Args, Debug, Clone)]
pub struct Link {
    #[command(flatten)]
    pub target: Target,
    /// Show URLs from history in full instead of hiding query strings and fragments.
    #[arg(long)]
    pub full_urls: bool,
}

#[derive(Args, Debug, Clone)]
pub struct Change {
    /// Show the change without writing it.
    #[arg(long)]
    pub dry_run: bool,
    /// Exit 5 without writing unless the configuration still has this revision, from any --json
    /// output.
    #[arg(long, value_name = "REVISION")]
    pub if_revision: Option<String>,
}

#[derive(ValueEnum, Clone, Copy, Debug)]
pub enum Match {
    Domain,
    Contains,
    Exact,
}

impl From<Match> for Condition {
    fn from(m: Match) -> Self {
        match m {
            Match::Domain => Condition::Domain,
            Match::Contains => Condition::Contains,
            Match::Exact => Condition::Exact,
        }
    }
}

#[derive(Args, Debug)]
pub struct Explain {
    #[command(flatten)]
    pub link: Link,
}

#[derive(Args, Debug)]
pub struct Route {
    #[command(flatten)]
    pub link: Link,
    /// The profile: a directory identifier such as "Profile 2", or an unambiguous display name.
    #[arg(long)]
    pub profile: String,
    /// The browser: a path, id, or name. Omit it to inherit the default browser.
    #[arg(long)]
    pub browser: Option<String>,
    /// How the rule matches the URL.
    #[arg(long = "match", value_enum, default_value = "domain")]
    pub condition: Match,
    /// The pattern. Defaults to the URL's host for domain (pass a parent domain to widen it) and
    /// the full URL for exact. Required for contains.
    #[arg(long)]
    pub value: Option<String>,
    /// Add the rule even if it stops later rules from ever matching.
    #[arg(long)]
    pub allow_shadowing: bool,
    #[command(flatten)]
    pub change: Change,
}

#[derive(Subcommand, Debug)]
pub enum Rules {
    /// List the rules in order, with each destination and whether it still resolves.
    List,
    /// Change a rule's destination or pattern.
    Update(RulesUpdate),
    /// Move a rule to another position.
    Move {
        /// The rule's current position.
        from: usize,
        /// The position it should have afterward.
        to: usize,
        #[command(flatten)]
        change: Change,
    },
    /// Remove a rule.
    Remove {
        /// The rule's position.
        position: usize,
        #[command(flatten)]
        change: Change,
    },
}

#[derive(Args, Debug)]
pub struct RulesUpdate {
    /// The rule's position, as `rules list` shows it.
    pub position: usize,
    /// The profile, resolved in the rule's browser after any browser change.
    #[arg(long)]
    pub profile: Option<String>,
    /// Give the rule its own browser: a path, id, or name. Requires --profile.
    #[arg(long, conflicts_with = "default_browser", requires = "profile")]
    pub browser: Option<String>,
    /// Make the rule inherit the default browser. Requires --profile.
    #[arg(long, requires = "profile")]
    pub default_browser: bool,
    /// How the rule matches the URL.
    #[arg(long = "match", value_enum)]
    pub condition: Option<Match>,
    /// The pattern.
    #[arg(long)]
    pub value: Option<String>,
    /// Change the rule even if it stops later rules from ever matching.
    #[arg(long)]
    pub allow_shadowing: bool,
    #[command(flatten)]
    pub change: Change,
}

#[derive(Args, Debug)]
pub struct Default {
    /// The default browser: a path, id, or name.
    #[arg(long)]
    pub browser: Option<String>,
    /// The default profile, resolved in the default browser.
    #[arg(long)]
    pub profile: Option<String>,
    #[command(flatten)]
    pub change: Change,
}

#[derive(Args, Debug)]
pub struct Profiles {
    /// Only list this browser: a path, id, or name.
    #[arg(long)]
    pub browser: Option<String>,
}

#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct History {
    #[command(subcommand)]
    pub action: Option<HistoryAction>,
    #[command(flatten)]
    pub list: HistoryList,
}

#[derive(Subcommand, Debug)]
pub enum HistoryAction {
    /// List recent links, newest first (the default).
    List(HistoryList),
    /// Delete the history file. Works even while history is off.
    Clear {
        /// Show what would be deleted without deleting it.
        #[arg(long)]
        dry_run: bool,
    },
    /// Start recording opened links (the default).
    On(Change),
    /// Stop recording opened links. Existing history is kept until cleared.
    Off(Change),
}

#[derive(Args, Debug, Clone)]
pub struct HistoryList {
    /// The number of entries to show.
    #[arg(long, default_value_t = 20, value_parser = clap::value_parser!(u32).range(1..))]
    pub limit: u32,
    /// Show URLs in full, including query strings and fragments.
    #[arg(long)]
    pub full_urls: bool,
}

#[derive(Subcommand, Debug)]
pub enum Picker {
    /// Show the picker's shortcut, favorites, and which destinations it shows.
    Show,
    /// Set the global shortcut that opens the picker, such as ctrl+alt+space.
    Shortcut {
        shortcut: String,
        #[command(flatten)]
        change: Change,
    },
    /// Pin a destination at the top of the picker.
    Favorite {
        /// The browser: a path, id, or name.
        #[arg(long)]
        browser: String,
        /// The profile, resolved in that browser.
        #[arg(long)]
        profile: String,
        /// The label to show. Defaults to the profile's display name.
        #[arg(long)]
        name: Option<String>,
        #[command(flatten)]
        change: Change,
    },
    /// Unpin a favorite.
    Unfavorite {
        #[arg(long)]
        browser: String,
        #[arg(long)]
        profile: String,
        #[command(flatten)]
        change: Change,
    },
    /// Show or hide a destination in the picker.
    Destination {
        #[arg(long)]
        browser: String,
        #[arg(long)]
        profile: String,
        /// Hide it instead of showing it.
        #[arg(long)]
        hide: bool,
        #[command(flatten)]
        change: Change,
    },
    /// Show every installed destination again.
    ShowAll(Change),
}

#[derive(Subcommand, Debug)]
pub enum Skill {
    /// Install or update the skill for each agent found. Safe to repeat.
    Setup(SkillArgs),
    /// Report each skill as current, outdated, missing, or foreign.
    Status(SkillAgent),
    /// Remove the skills that setup installed.
    Remove(SkillArgs),
    /// Print the routing guide for agents.
    Show,
}

#[derive(Args, Debug)]
pub struct SkillAgent {
    /// Only this agent.
    #[arg(long, value_enum)]
    pub agent: Option<crate::skill::Agent>,
}

#[derive(Args, Debug)]
pub struct SkillArgs {
    #[command(flatten)]
    pub agent: SkillAgent,
    /// Show what would change without changing it.
    #[arg(long)]
    pub dry_run: bool,
}
