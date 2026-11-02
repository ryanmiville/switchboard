//! Rules that can never match because an earlier rule matches every link they would.

use crate::config::{Condition, Rule};
use crate::router;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Unreachable {
    /// 0-based index of the rule that never matches.
    pub rule: usize,
    /// 0-based index of the earlier rule that always matches first.
    pub by: usize,
}

/// Whether `earlier` matches every link `later` would.
pub fn covers(earlier: &Rule, later: &Rule) -> bool {
    let first = earlier.value.to_lowercase();
    let second = later.value.to_lowercase();
    if first.is_empty() || second.is_empty() {
        return false;
    }
    match (earlier.condition, later.condition) {
        // An exact rule matches one link; it is hidden if the earlier rule matches that link.
        (_, Condition::Exact) => router::matches(earlier, &later.value),
        // Every link a domain rule matches contains its domain.
        (Condition::Contains, Condition::Contains | Condition::Domain) => second.contains(&first),
        (Condition::Domain, Condition::Domain) => {
            second == first || second.strip_suffix(&first).is_some_and(|p| p.ends_with('.'))
        }
        (Condition::Domain | Condition::Exact, Condition::Contains)
        | (Condition::Exact, Condition::Domain) => false,
    }
}

pub fn unreachable(rules: &[Rule]) -> Vec<Unreachable> {
    (0..rules.len())
        .filter_map(|later| {
            rules[..later]
                .iter()
                .position(|e| covers(e, &rules[later]))
                .map(|by| Unreachable { rule: later, by })
        })
        .collect()
}

/// Rules unreachable in `after` that weren't already unreachable in `before`, followed by id.
pub fn newly_unreachable(before: &[Rule], after: &[Rule]) -> Vec<Unreachable> {
    let existing: Vec<_> = unreachable(before).iter().map(|u| before[u.rule].id).collect();
    unreachable(after).into_iter().filter(|u| !existing.contains(&after[u.rule].id)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rule(condition: Condition, value: &str) -> Rule {
        Rule::new(condition, value, "P")
    }

    #[test]
    fn a_parent_domain_hides_its_subdomains_but_not_the_reverse() {
        assert!(covers(&rule(Condition::Domain, "github.com"), &rule(Condition::Domain, "docs.github.com")));
        assert!(!covers(&rule(Condition::Domain, "docs.github.com"), &rule(Condition::Domain, "github.com")));
        assert!(!covers(&rule(Condition::Domain, "hub.com"), &rule(Condition::Domain, "github.com")));
    }

    #[test]
    fn a_contains_rule_hides_rules_whose_text_includes_it() {
        assert!(covers(&rule(Condition::Contains, "acme"), &rule(Condition::Contains, "acme/api")));
        assert!(covers(&rule(Condition::Contains, "github"), &rule(Condition::Domain, "github.com")));
        assert!(!covers(&rule(Condition::Domain, "github.com"), &rule(Condition::Contains, "github.com")));
    }

    #[test]
    fn an_exact_rule_is_hidden_when_an_earlier_rule_matches_its_link() {
        assert!(covers(&rule(Condition::Domain, "x.com"), &rule(Condition::Exact, "https://x.com/a")));
        assert!(!covers(&rule(Condition::Domain, "y.com"), &rule(Condition::Exact, "https://x.com/a")));
    }

    #[test]
    fn only_newly_hidden_rules_are_reported() {
        let a = rule(Condition::Domain, "docs.github.com");
        let b = rule(Condition::Domain, "github.com");
        let before = vec![b.clone(), a.clone()];
        assert_eq!(unreachable(&before), vec![Unreachable { rule: 1, by: 0 }]);
        assert!(newly_unreachable(&before, &before).is_empty());
        let after = vec![a, b.clone(), rule(Condition::Domain, "api.github.com")];
        assert_eq!(newly_unreachable(&[b], &after), vec![Unreachable { rule: 2, by: 1 }]);
    }
}
