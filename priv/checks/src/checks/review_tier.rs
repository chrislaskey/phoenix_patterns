//! Review tier: which review a branch needs, from the paths it changed.
//!
//! Every path is tested against the tiers from `protected` down to `low`, and
//! the first tier with a matching pattern wins. Paths that match nothing get
//! the default tier. The branch's tier is the highest tier of any path. All
//! of this is printed as `info`.
//!
//! One rule fails the run: a path in a `protected` group must be the only
//! kind of change. Several paths from the same group may change together,
//! nothing else may change with them.
//!
//! Settings, given as `--set review_tier.KEY=VALUE`:
//!
//! - `default`: `high` (when not set) or `standard`, for unmatched paths
//! - `protected.NAME`: a pattern in the protected group called NAME
//! - `high`, `standard`, `low`: a pattern in that tier
//!
//! Patterns match the whole path from the repository root. `*` does not
//! cross a `/`, `**` does.

use std::fmt;
use std::path::Path;

use globset::{Glob, GlobBuilder, GlobSet, GlobSetBuilder};

use crate::check::{Branch, BranchCheck, Confidence, Finding, Kind, Settings};

pub struct ReviewTier;

/// The check this file contributes. Every file in `src/checks/` exports one.
pub const CHECK: Kind = Kind::Branch(&ReviewTier);

impl BranchCheck for ReviewTier {
    fn name(&self) -> &'static str {
        "review_tier"
    }

    fn settings(&self) -> &'static [&'static str] {
        &["default", "protected.*", "high", "standard", "low"]
    }

    fn run(&self, branch: &Branch, settings: &Settings) -> Result<Vec<Finding>, String> {
        let rules = Rules::from_settings(settings)?;
        Ok(classify(&rules, branch))
    }
}

/// Lowest to highest, so the derived order is the review order.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
enum Tier {
    Low,
    Standard,
    High,
    Protected,
}

impl fmt::Display for Tier {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Tier::Low => "low",
            Tier::Standard => "standard",
            Tier::High => "high",
            Tier::Protected => "protected",
        })
    }
}

struct Rules {
    default: Tier,
    /// Group name and its patterns, in the order the settings gave them.
    protected: Vec<(String, GlobSet)>,
    high: GlobSet,
    standard: GlobSet,
    low: GlobSet,
}

/// Where one path landed.
struct Placed<'a> {
    path: &'a Path,
    tier: Tier,
    /// Index into `Rules::protected` when the tier is `Protected`.
    group: Option<usize>,
    /// False when the default tier applied because nothing matched.
    matched: bool,
}

impl Rules {
    fn from_settings(settings: &Settings) -> Result<Self, String> {
        let default = match settings.one("default") {
            None | Some("high") => Tier::High,
            Some("standard") => Tier::Standard,
            Some(other) => {
                return Err(format!(
                    "review_tier.default must be high or standard, got {other}"
                ));
            }
        };

        let mut groups: Vec<(String, GlobSetBuilder)> = Vec::new();
        for (group, pattern) in settings.under("protected") {
            let glob = glob(&format!("protected.{group}"), pattern)?;
            match groups.iter_mut().find(|(name, _)| name == group) {
                Some((_, builder)) => {
                    builder.add(glob);
                }
                None => {
                    let mut builder = GlobSetBuilder::new();
                    builder.add(glob);
                    groups.push((group.to_string(), builder));
                }
            }
        }
        let protected = groups
            .into_iter()
            .map(|(name, builder)| build(builder).map(|set| (name, set)))
            .collect::<Result<Vec<_>, _>>()?;

        Ok(Self {
            default,
            protected,
            high: tier_set(settings, "high")?,
            standard: tier_set(settings, "standard")?,
            low: tier_set(settings, "low")?,
        })
    }

    fn place<'a>(&self, path: &'a Path) -> Placed<'a> {
        let placed = |tier, group, matched| Placed {
            path,
            tier,
            group,
            matched,
        };

        if let Some(index) = self.protected.iter().position(|(_, set)| set.is_match(path)) {
            placed(Tier::Protected, Some(index), true)
        } else if self.high.is_match(path) {
            placed(Tier::High, None, true)
        } else if self.standard.is_match(path) {
            placed(Tier::Standard, None, true)
        } else if self.low.is_match(path) {
            placed(Tier::Low, None, true)
        } else {
            placed(self.default, None, false)
        }
    }

    fn group_name(&self, index: usize) -> &str {
        &self.protected[index].0
    }
}

fn tier_set(settings: &Settings, key: &str) -> Result<GlobSet, String> {
    let mut builder = GlobSetBuilder::new();
    for pattern in settings.many(key) {
        builder.add(glob(key, pattern)?);
    }
    build(builder)
}

fn glob(setting: &str, pattern: &str) -> Result<Glob, String> {
    GlobBuilder::new(pattern)
        .literal_separator(true)
        .build()
        .map_err(|error| {
            format!(
                "review_tier.{setting}: {pattern} is not a valid pattern: {}",
                error.kind()
            )
        })
}

fn build(builder: GlobSetBuilder) -> Result<GlobSet, String> {
    builder.build().map_err(|error| error.to_string())
}

/// One `info` finding per path, the `review tier:` line, then one confirmed
/// finding per path that breaks the protected rule.
fn classify(rules: &Rules, branch: &Branch) -> Vec<Finding> {
    let mut placed: Vec<Placed> = branch.paths.iter().map(|path| rules.place(path)).collect();
    placed.sort_by(|a, b| a.tier.cmp(&b.tier).then_with(|| a.path.cmp(b.path)));

    let mut findings: Vec<Finding> = placed
        .iter()
        .map(|p| {
            let message = match (p.tier, p.group, p.matched) {
                (Tier::Protected, Some(group), _) => {
                    format!("protected, group {}", rules.group_name(group))
                }
                (tier, _, true) => tier.to_string(),
                (tier, _, false) => format!("{tier}, no rule matched so the default applies"),
            };
            Finding::about(p.path, Confidence::Info, message)
        })
        .collect();

    let tier = match placed.last() {
        Some(p) => p.tier.to_string(),
        None => "none".to_string(),
    };
    findings.push(Finding::info(format!(
        "review tier: {tier}, {} file(s) changed against {}",
        placed.len(),
        branch.base
    )));

    // The list is sorted by tier then path, so the first protected path is
    // the lowest sorted one. Its group is the one everything else must be in.
    if let Some(anchor) = placed.iter().find(|p| p.tier == Tier::Protected) {
        let group = anchor.group.expect("protected paths always have a group");
        let group_name = rules.group_name(group);
        let anchor_path = anchor.path.display();

        for p in &placed {
            let message = match p.group {
                Some(other) if other == group => continue,
                Some(other) => format!(
                    "protected group \"{}\" cannot change with {anchor_path} from group \"{group_name}\"; change one group per pull request",
                    rules.group_name(other)
                ),
                None => format!(
                    "{anchor_path} is in the protected group \"{group_name}\", so it must be the only change; move this file to its own branch"
                ),
            };
            findings.push(Finding::about(p.path, Confidence::Confirmed, message));
        }
    }

    findings
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::check::Confidence::{Confirmed, Info};
    use crate::check::testing::{branch, messages, settings};

    fn run(entries: &[(&str, &str)], paths: &[&str]) -> Vec<Finding> {
        ReviewTier
            .run(&branch(paths), &settings(entries))
            .expect("settings are valid")
    }

    #[test]
    fn the_higher_tier_wins_when_patterns_overlap() {
        let findings = run(
            &[("high", "test/support/**"), ("standard", "test/**")],
            &["test/support/data_case.ex", "test/example/orders_test.exs"],
        );
        assert_eq!(
            messages(&findings, Info),
            vec![
                "test/example/orders_test.exs: standard",
                "test/support/data_case.ex: high",
                "review tier: high, 2 file(s) changed against origin/main",
            ]
        );
    }

    #[test]
    fn a_low_pattern_cannot_pull_a_file_out_of_a_higher_tier() {
        let findings = run(
            &[
                ("high", "lib/example_web/components/**"),
                ("low", "lib/example_web/**/*.heex"),
            ],
            &["lib/example_web/components/layouts/root.html.heex"],
        );
        assert_eq!(
            messages(&findings, Info)[0],
            "lib/example_web/components/layouts/root.html.heex: high"
        );
    }

    #[test]
    fn unmatched_paths_get_the_default_and_say_so() {
        let findings = run(&[("low", "docs/**")], &["Dockerfile"]);
        assert_eq!(
            messages(&findings, Info),
            vec![
                "Dockerfile: high, no rule matched so the default applies",
                "review tier: high, 1 file(s) changed against origin/main",
            ]
        );
    }

    #[test]
    fn the_default_can_be_standard_but_nothing_else() {
        let findings = run(&[("default", "standard")], &["Dockerfile"]);
        assert_eq!(
            messages(&findings, Info)[0],
            "Dockerfile: standard, no rule matched so the default applies"
        );

        let error = ReviewTier
            .run(&branch(&[]), &settings(&[("default", "low")]))
            .unwrap_err();
        assert_eq!(error, "review_tier.default must be high or standard, got low");
    }

    #[test]
    fn an_invalid_pattern_is_an_error_naming_the_setting() {
        let error = ReviewTier
            .run(&branch(&[]), &settings(&[("protected.agents", "[")]))
            .unwrap_err();
        assert!(error.starts_with("review_tier.protected.agents: [ is not a valid pattern"));
    }

    #[test]
    fn no_changes_is_tier_none() {
        let findings = run(&[], &[]);
        assert_eq!(
            messages(&findings, Info),
            vec!["review tier: none, 0 file(s) changed against origin/main"]
        );
        assert!(messages(&findings, Confirmed).is_empty());
    }

    #[test]
    fn files_from_one_protected_group_may_change_together() {
        let findings = run(
            &[
                ("protected.lint_config", ".credo.exs"),
                ("protected.lint_config", ".check.exs"),
            ],
            &[".check.exs", ".credo.exs"],
        );
        assert_eq!(
            messages(&findings, Info),
            vec![
                ".check.exs: protected, group lint_config",
                ".credo.exs: protected, group lint_config",
                "review tier: protected, 2 file(s) changed against origin/main",
            ]
        );
        assert!(messages(&findings, Confirmed).is_empty());
    }

    #[test]
    fn a_protected_file_mixed_with_anything_else_fails_on_the_other_files() {
        let findings = run(
            &[("protected.agents", "AGENTS.md"), ("standard", "lib/**")],
            &["lib/example/orders.ex", "AGENTS.md", "lib/example/users.ex"],
        );
        assert_eq!(
            messages(&findings, Confirmed),
            vec![
                "lib/example/orders.ex: AGENTS.md is in the protected group \"agents\", so it must be the only change; move this file to its own branch",
                "lib/example/users.ex: AGENTS.md is in the protected group \"agents\", so it must be the only change; move this file to its own branch",
            ]
        );
    }

    #[test]
    fn two_protected_groups_cannot_change_together() {
        let findings = run(
            &[
                ("protected.agents", "AGENTS.md"),
                ("protected.lint_config", ".credo.exs"),
            ],
            &[".credo.exs", "AGENTS.md"],
        );
        assert_eq!(
            messages(&findings, Confirmed),
            vec![
                "AGENTS.md: protected group \"agents\" cannot change with .credo.exs from group \"lint_config\"; change one group per pull request",
            ]
        );
    }

    #[test]
    fn a_single_star_does_not_cross_directories() {
        let findings = run(
            &[("protected.agents", "AGENTS.md"), ("high", "config/**")],
            &["docs/AGENTS.md", "configs/dev.exs", "config/dev.exs"],
        );
        assert_eq!(
            messages(&findings, Info),
            vec![
                "config/dev.exs: high",
                "configs/dev.exs: high, no rule matched so the default applies",
                "docs/AGENTS.md: high, no rule matched so the default applies",
                "review tier: high, 3 file(s) changed against origin/main",
            ]
        );
    }

    #[test]
    fn a_double_star_matches_zero_or_more_directories() {
        let findings = run(
            &[("low", "lib/example_web/live/**/*.heex")],
            &[
                "lib/example_web/live/home.html.heex",
                "lib/example_web/live/orders/index.html.heex",
            ],
        );
        assert_eq!(
            messages(&findings, Info),
            vec![
                "lib/example_web/live/home.html.heex: low",
                "lib/example_web/live/orders/index.html.heex: low",
                "review tier: low, 2 file(s) changed against origin/main",
            ]
        );
    }
}
