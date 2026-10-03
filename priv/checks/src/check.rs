//! The contract every check implements.
//!
//! There are two kinds of check, named after what they are given:
//!
//! - A **source check** is given one source file. It runs a fast pass on
//!   every file and a slow pass on the files the fast pass flagged.
//! - A **branch check** is given the branch: every path it changed compared
//!   with a base. It runs once.

use std::path::PathBuf;

/// A source file, read once and shared by every source check.
pub struct SourceFile {
    pub path: PathBuf,
    pub contents: String,
}

impl SourceFile {
    /// The 1-based line number of the byte at `offset`.
    pub fn line_of(&self, offset: usize) -> usize {
        self.contents[..offset].matches('\n').count() + 1
    }
}

/// The branch: every path it changed, compared with `base`. Committed,
/// staged, unstaged and untracked changes all count. Built once by the
/// runner and shared by every branch check.
#[derive(Debug)]
pub struct Branch {
    pub base: String,
    pub paths: Vec<PathBuf>,
}

/// How sure a check is that a finding is real.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Confidence {
    /// A real problem. Fails the run.
    Confirmed,
    /// Might be a problem. The slow pass decides.
    Potential,
    /// Not a problem, just something worth printing. Never fails the run.
    Info,
}

/// One finding. Source checks leave `path` empty because the runner knows
/// which file it gave them. Branch checks set it. Either may leave `line`
/// empty when the finding is about a whole file, or `path` empty too when it
/// is about the whole run.
#[derive(Debug, PartialEq, Eq)]
pub struct Finding {
    pub path: Option<PathBuf>,
    pub line: Option<usize>,
    pub message: String,
    pub confidence: Confidence,
}

impl Finding {
    /// A confirmed finding on a line of the file being checked.
    pub fn confirmed(line: usize, message: impl Into<String>) -> Self {
        Self::new(None, Some(line), message, Confidence::Confirmed)
    }

    /// A potential finding on a line of the file being checked.
    pub fn potential(line: usize, message: impl Into<String>) -> Self {
        Self::new(None, Some(line), message, Confidence::Potential)
    }

    /// A finding about a whole file, for branch checks.
    pub fn about(
        path: impl Into<PathBuf>,
        confidence: Confidence,
        message: impl Into<String>,
    ) -> Self {
        Self::new(Some(path.into()), None, message, confidence)
    }

    /// Information about the whole run, with no file or line.
    pub fn info(message: impl Into<String>) -> Self {
        Self::new(None, None, message, Confidence::Info)
    }

    fn new(
        path: Option<PathBuf>,
        line: Option<usize>,
        message: impl Into<String>,
        confidence: Confidence,
    ) -> Self {
        Self {
            path,
            line,
            message: message.into(),
            confidence,
        }
    }
}

/// A rule about one source file.
///
/// `fast` runs on every file and must never miss a real problem: when unsure,
/// return a `Potential` finding. `slow` runs only on files where `fast` returned
/// a `Potential` finding, and returns only the findings it can confirm.
pub trait SourceCheck: Sync {
    /// Short identifier shown next to each finding, e.g. `core_component_tags`.
    fn name(&self) -> &'static str;

    /// The setting keys this check accepts, without the check name. A key
    /// ending in `.*` accepts any single segment there. A setting outside
    /// this list stops the run before any check runs.
    fn settings(&self) -> &'static [&'static str] {
        &[]
    }

    /// Runs once, before any file is scanned, with the check's settings. A
    /// check that needs more than the file in front of it, such as a list of
    /// names read from one module, reads it here and keeps it. Returns `Err`
    /// with a message when the settings cannot be used, which stops the run
    /// with exit code 2.
    fn prepare(&self, _settings: &Settings) -> Result<(), String> {
        Ok(())
    }

    /// Cheap scan. Over-reporting is fine, missing a real problem is not.
    fn fast(&self, file: &SourceFile) -> Vec<Finding>;

    /// Thorough scan of a flagged file. Return confirmed findings only.
    fn slow(&self, file: &SourceFile) -> Vec<Finding>;
}

/// A rule about what a branch changed.
pub trait BranchCheck: Sync {
    /// Short identifier shown next to each finding, e.g. `review_tier`.
    fn name(&self) -> &'static str;

    /// The setting keys this check accepts, without the check name. A key
    /// ending in `.*` accepts any single segment there, so `protected.*`
    /// accepts `protected.agents`. A setting outside this list stops the run
    /// before any check runs.
    fn settings(&self) -> &'static [&'static str] {
        &[]
    }

    /// Runs once over the branch. Branch checks get their settings here
    /// rather than in a separate step, since they only run once. Returns `Err` with a message when the
    /// settings cannot be used, which stops the run with exit code 2.
    fn run(&self, branch: &Branch, settings: &Settings) -> Result<Vec<Finding>, String>;
}

/// A check of either kind. Every file in `src/checks/` exports one as `CHECK`.
#[derive(Clone, Copy)]
pub enum Kind {
    Source(&'static dyn SourceCheck),
    Branch(&'static dyn BranchCheck),
}

impl Kind {
    pub fn name(&self) -> &'static str {
        match self {
            Kind::Source(check) => check.name(),
            Kind::Branch(check) => check.name(),
        }
    }

    pub fn settings(&self) -> &'static [&'static str] {
        match self {
            Kind::Source(check) => check.settings(),
            Kind::Branch(check) => check.settings(),
        }
    }
}

/// The settings for one check, from `--set CHECK.KEY=VALUE`, with the check
/// name removed from every key. Order is kept, and a key may repeat.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Settings {
    entries: Vec<(String, String)>,
}

impl Settings {
    pub fn new(entries: Vec<(String, String)>) -> Self {
        Self { entries }
    }

    /// The last value given for `key`, so a later `--set` overrides an
    /// earlier one.
    pub fn one(&self, key: &str) -> Option<&str> {
        self.entries
            .iter()
            .rev()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
    }

    /// Every value given for `key`, in order.
    pub fn many(&self, key: &str) -> Vec<&str> {
        self.entries
            .iter()
            .filter(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
            .collect()
    }

    /// Every `(rest of key, value)` whose key starts with `prefix.`, in
    /// order. `under("protected")` on `protected.agents=AGENTS.md` yields
    /// `("agents", "AGENTS.md")`.
    pub fn under(&self, prefix: &str) -> Vec<(&str, &str)> {
        let prefix = format!("{prefix}.");
        self.entries
            .iter()
            .filter_map(|(k, v)| {
                k.strip_prefix(prefix.as_str())
                    .map(|rest| (rest, v.as_str()))
            })
            .collect()
    }

    /// Whether `key` is in `accepted`, where an entry ending in `.*` accepts
    /// any one more segment.
    pub fn accepts(accepted: &[&str], key: &str) -> bool {
        accepted
            .iter()
            .any(|pattern| match pattern.strip_suffix(".*") {
                Some(prefix) => key
                    .strip_prefix(prefix)
                    .and_then(|rest| rest.strip_prefix('.'))
                    .is_some_and(|rest| !rest.is_empty() && !rest.contains('.')),
                None => *pattern == key,
            })
    }
}

/// Helpers for unit testing a check with inline source snippets.
#[cfg(test)]
pub mod testing {
    use super::*;

    /// A file built from a snippet. The path only matters for its extension.
    pub fn source(path: &str, contents: &str) -> SourceFile {
        SourceFile {
            path: PathBuf::from(path),
            contents: contents.to_string(),
        }
    }

    /// The line numbers of the findings with the given confidence.
    pub fn lines(findings: &[Finding], confidence: Confidence) -> Vec<usize> {
        findings
            .iter()
            .filter(|f| f.confidence == confidence)
            .filter_map(|f| f.line)
            .collect()
    }

    /// The line numbers a full run would confirm: the fast pass, then the
    /// slow pass if the fast pass left anything potential.
    pub fn run(check: &dyn SourceCheck, path: &str, contents: &str) -> Vec<usize> {
        let file = source(path, contents);
        let fast = check.fast(&file);
        let mut confirmed = lines(&fast, Confidence::Confirmed);
        if !lines(&fast, Confidence::Potential).is_empty() {
            confirmed.extend(lines(&check.slow(&file), Confidence::Confirmed));
        }
        confirmed.sort_unstable();
        confirmed.dedup();
        confirmed
    }

    /// A branch that changed these paths.
    pub fn branch(paths: &[&str]) -> Branch {
        Branch {
            base: "origin/main".to_string(),
            paths: paths.iter().map(PathBuf::from).collect(),
        }
    }

    /// Settings from `(key, value)` pairs, already without the check name.
    pub fn settings(entries: &[(&str, &str)]) -> Settings {
        Settings::new(
            entries
                .iter()
                .map(|(k, v)| (k.to_string(), v.to_string()))
                .collect(),
        )
    }

    /// The messages of the findings with the given confidence, in order.
    pub fn messages(findings: &[Finding], confidence: Confidence) -> Vec<String> {
        findings
            .iter()
            .filter(|f| f.confidence == confidence)
            .map(|f| match &f.path {
                Some(path) => format!("{}: {}", path.display(), f.message),
                None => f.message.clone(),
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_exact_keys_and_one_segment_wildcards() {
        let accepted = &["default", "protected.*"];
        assert!(Settings::accepts(accepted, "default"));
        assert!(Settings::accepts(accepted, "protected.agents"));
        assert!(!Settings::accepts(accepted, "protected"));
        assert!(!Settings::accepts(accepted, "protected.a.b"));
        assert!(!Settings::accepts(accepted, "base"));
    }

    #[test]
    fn later_values_win_for_one_and_all_are_kept_for_many() {
        let settings = testing::settings(&[
            ("default", "high"),
            ("high", "a"),
            ("default", "standard"),
            ("high", "b"),
        ]);
        assert_eq!(settings.one("default"), Some("standard"));
        assert_eq!(settings.many("high"), vec!["a", "b"]);
        assert_eq!(settings.one("missing"), None);
    }

    #[test]
    fn under_strips_the_prefix_and_keeps_order() {
        let settings = testing::settings(&[
            ("protected.agents", "AGENTS.md"),
            ("high", "x"),
            ("protected.lint_config", ".credo.exs"),
            ("protected.lint_config", ".check.exs"),
        ]);
        assert_eq!(
            settings.under("protected"),
            vec![
                ("agents", "AGENTS.md"),
                ("lint_config", ".credo.exs"),
                ("lint_config", ".check.exs")
            ]
        );
    }
}
