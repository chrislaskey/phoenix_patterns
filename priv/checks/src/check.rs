//! The contract every check implements.

use std::path::PathBuf;

/// A source file, read once and shared by every check.
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

/// How sure a check is that a finding is real.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Confidence {
    /// A real problem. Fails the run.
    Confirmed,
    /// Might be a problem. The slow pass decides.
    Potential,
}

/// One problem in one file.
#[derive(Debug, PartialEq, Eq)]
pub struct Finding {
    pub line: usize,
    pub message: String,
    pub confidence: Confidence,
}

impl Finding {
    pub fn confirmed(line: usize, message: impl Into<String>) -> Self {
        Self {
            line,
            message: message.into(),
            confidence: Confidence::Confirmed,
        }
    }

    pub fn potential(line: usize, message: impl Into<String>) -> Self {
        Self {
            line,
            message: message.into(),
            confidence: Confidence::Potential,
        }
    }
}

/// A rule about the source code.
///
/// `fast` runs on every file and must never miss a real problem: when unsure,
/// return a `Potential` finding. `slow` runs only on files where `fast` returned
/// a `Potential` finding, and returns only the findings it can confirm.
pub trait Check: Sync {
    /// Short identifier shown next to each finding, e.g. `raw_html_tags`.
    fn name(&self) -> &'static str;

    /// Cheap scan. Over-reporting is fine, missing a real problem is not.
    fn fast(&self, file: &SourceFile) -> Vec<Finding>;

    /// Thorough scan of a flagged file. Return confirmed findings only.
    fn slow(&self, file: &SourceFile) -> Vec<Finding>;
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
            .map(|f| f.line)
            .collect()
    }

    /// The line numbers a full run would confirm: the fast pass, then the
    /// slow pass if the fast pass left anything potential.
    pub fn run(check: &dyn Check, path: &str, contents: &str) -> Vec<usize> {
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
}
