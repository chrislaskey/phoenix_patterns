//! Example check: raw `<p>` and `<h1>`..`<h6>` tags in `.heex` templates.
//!
//! Fast pass: substring search for `<p` and `<h`. A match followed by `>`,
//! whitespace, or `/` is confirmed. Anything else (`<pre`, `<path`, `<h1`,
//! `<header`) is potential.
//!
//! Slow pass: reads the whole tag name after `<` and confirms only exact
//! matches. This stands in for a real parser.

use crate::check::{Check, Finding, SourceFile};

pub struct RawHtmlTags;

/// The check this file contributes. Every file in `src/checks/` exports one.
pub const CHECK: &dyn Check = &RawHtmlTags;

const TAGS: &[&str] = &["p", "h1", "h2", "h3", "h4", "h5", "h6"];

impl Check for RawHtmlTags {
    fn name(&self) -> &'static str {
        "raw_html_tags"
    }

    fn fast(&self, file: &SourceFile) -> Vec<Finding> {
        if !is_template(file) {
            return Vec::new();
        }

        ["<p", "<h"]
            .iter()
            .flat_map(|needle| file.contents.match_indices(needle))
            .map(|(offset, needle)| {
                let line = file.line_of(offset);
                let next = file.contents[offset + needle.len()..].chars().next();
                if next.is_none_or(ends_tag) {
                    Finding::confirmed(line, message(&needle[1..]))
                } else {
                    Finding::potential(line, format!("{needle} may be a raw tag"))
                }
            })
            .collect()
    }

    fn slow(&self, file: &SourceFile) -> Vec<Finding> {
        file.contents
            .match_indices('<')
            .filter_map(|(offset, _)| {
                let rest = &file.contents[offset + 1..];
                let name: String = rest.chars().take_while(|c| c.is_alphanumeric()).collect();
                let complete = rest[name.len()..].chars().next().is_none_or(ends_tag);

                (complete && TAGS.contains(&name.as_str()))
                    .then(|| Finding::confirmed(file.line_of(offset), message(&name)))
            })
            .collect()
    }
}

/// Whether `c` can follow a tag name.
fn ends_tag(c: char) -> bool {
    c == '>' || c == '/' || c.is_whitespace()
}

fn is_template(file: &SourceFile) -> bool {
    file.path.extension().is_some_and(|ext| ext == "heex")
}

fn message(tag: &str) -> String {
    format!("<{tag}> is a raw tag, use <.{tag}> from CoreComponents")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::check::Confidence::{Confirmed, Potential};
    use crate::check::testing::{lines, run, source};

    #[test]
    fn fast_confirms_a_tag_it_can_read_fully() {
        let file = source("a.heex", "<p class=\"x\">hi</p>\n<h1>\n");
        let findings = RawHtmlTags.fast(&file);
        assert_eq!(lines(&findings, Confirmed), vec![1]);
        assert_eq!(lines(&findings, Potential), vec![2]);
    }

    #[test]
    fn fast_flags_lookalikes_as_potential() {
        let file = source("a.heex", "<pre>\n<path d=\"\" />\n<header>\n");
        assert_eq!(lines(&RawHtmlTags.fast(&file), Potential), vec![1, 2, 3]);
    }

    #[test]
    fn slow_clears_lookalikes_and_confirms_real_tags() {
        let file = source("a.heex", "<pre>\n<h1 class=\"x\">\n<header>\n<h2/>\n");
        assert_eq!(lines(&RawHtmlTags.slow(&file), Confirmed), vec![2, 4]);
    }

    #[test]
    fn ignores_files_that_are_not_templates() {
        assert!(RawHtmlTags.fast(&source("a.ex", "<p>")).is_empty());
    }

    #[test]
    fn full_run_reports_each_real_tag_once() {
        let confirmed = run(
            &RawHtmlTags,
            "a.heex",
            "<p class=\"x\">\n<pre>\n<h1>\n<html>\n",
        );
        assert_eq!(confirmed, vec![1, 3]);
    }
}
