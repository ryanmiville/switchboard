//! Rule matching. The first matching rule wins; otherwise the default destination.

use crate::config::{Condition, Config, Destination, Rule};
use crate::url;

/// Where a link goes, and the index of the rule that sent it there (`None` for the default).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Decision {
    pub destination: Destination,
    pub rule: Option<usize>,
}

pub fn decide(config: &Config, link: &str) -> Decision {
    let lowered = link.to_lowercase();
    let host = url::web_host(link);
    for (index, rule) in config.rules.iter().enumerate() {
        if matches_parts(rule, &lowered, host.as_deref()) {
            return Decision { destination: config.destination_of(rule), rule: Some(index) };
        }
    }
    Decision { destination: config.default_destination(), rule: None }
}

/// Whether `rule` matches `link`, ignoring every other rule.
pub fn matches(rule: &Rule, link: &str) -> bool {
    matches_parts(rule, &link.to_lowercase(), url::web_host(link).as_deref())
}

fn matches_parts(rule: &Rule, lowered: &str, host: Option<&str>) -> bool {
    let value = rule.value.to_lowercase();
    if value.is_empty() {
        return false;
    }
    match rule.condition {
        Condition::Contains => lowered.contains(&value),
        Condition::Exact => lowered == value,
        Condition::Domain => {
            host.is_some_and(|h| h == value || h.strip_suffix(&value).is_some_and(|p| p.ends_with('.')))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config(rules: Vec<Rule>) -> Config {
        Config { browser: "/Applications/Helium.app".into(), rules, ..Config::default() }
    }

    #[test]
    fn the_first_matching_rule_wins() {
        let c = config(vec![
            Rule::new(Condition::Contains, "acme", "A"),
            Rule::new(Condition::Domain, "github.com", "B"),
        ]);
        let d = decide(&c, "https://github.com/acme/api");
        assert_eq!(d.rule, Some(0));
        assert_eq!(d.destination.profile, "A");
    }

    #[test]
    fn unmatched_links_use_the_default_destination() {
        let c = config(vec![Rule::new(Condition::Domain, "github.com", "B")]);
        let d = decide(&c, "https://example.com");
        assert_eq!(d, Decision { destination: c.default_destination(), rule: None });
    }

    #[test]
    fn domain_rules_match_the_host_and_subdomains_at_a_dot() {
        let rule = Rule::new(Condition::Domain, "GitHub.com", "P");
        assert!(matches(&rule, "https://github.com/x"));
        assert!(matches(&rule, "https://docs.GITHUB.com"));
        assert!(!matches(&rule, "https://notgithub.com"));
        assert!(!matches(&rule, "https://example.com/github.com"));
        assert!(!matches(&rule, "ftp://github.com"));
    }

    #[test]
    fn contains_and_exact_compare_the_whole_link_ignoring_case() {
        assert!(matches(&Rule::new(Condition::Contains, "ACME", "P"), "https://x.com/?q=acme"));
        assert!(matches(&Rule::new(Condition::Exact, "https://x.com/A", "P"), "HTTPS://X.COM/a"));
        assert!(!matches(&Rule::new(Condition::Exact, "https://x.com", "P"), "https://x.com/"));
    }

    #[test]
    fn empty_patterns_never_match() {
        for condition in Condition::ALL {
            assert!(!matches(&Rule::new(condition, "", "P"), "https://x.com"));
        }
    }

    #[test]
    fn a_rule_without_a_browser_inherits_the_default_browser() {
        let c = config(vec![
            Rule::new(Condition::Domain, "a.com", "Default"),
            Rule::new(Condition::Domain, "b.com", "Profile 2")
                .with_browser("/Applications/Google Chrome.app"),
        ]);
        assert_eq!(decide(&c, "https://a.com").destination.browser, "/Applications/Helium.app");
        assert_eq!(decide(&c, "https://b.com").destination.browser, "/Applications/Google Chrome.app");
    }
}
