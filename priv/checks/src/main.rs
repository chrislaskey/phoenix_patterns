//! Runs every check in `checks::all()` over the given paths (default `lib`).
//!
//! Fast pass first, printing findings as each file finishes. Then the slow
//! pass over every file a check flagged as potential. Exits non-zero when any
//! finding is confirmed.

mod check;
mod checks;

use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use rayon::prelude::*;
use walkdir::WalkDir;

use check::{Check, Confidence, Finding, SourceFile};

const EXTENSIONS: &[&str] = &["ex", "exs", "heex"];

/// Directories never worth scanning, however deep they are.
const IGNORED_DIRS: &[&str] = &["_build", "deps", "node_modules"];

/// A (check, file) pair the fast pass could not settle.
struct Flagged {
    check: usize,
    file: usize,
    /// Confirmed by the fast pass and already printed, so the slow pass
    /// does not print them again.
    reported: Vec<Finding>,
}

fn main() -> ExitCode {
    let roots: Vec<PathBuf> = std::env::args_os().skip(1).map(PathBuf::from).collect();
    let roots = if roots.is_empty() {
        vec![PathBuf::from("lib")]
    } else {
        roots
    };

    let files = collect_files(&roots);
    let checks = checks::all();

    // Fast pass: every check on every file, in parallel, printing per file.
    let (fast_confirmed, flagged) = files
        .par_iter()
        .enumerate()
        .map(|(file_index, file)| {
            let mut confirmed = 0;
            let mut flagged = Vec::new();
            let mut out = io::stdout().lock();

            for (check_index, check) in checks.iter().enumerate() {
                let mut findings = check.fast(file);
                confirmed += report(&mut out, file, check.as_ref(), &mut findings);

                if findings
                    .iter()
                    .any(|f| f.confidence == Confidence::Potential)
                {
                    findings.retain(|f| f.confidence == Confidence::Confirmed);
                    flagged.push(Flagged {
                        check: check_index,
                        file: file_index,
                        reported: findings,
                    });
                }
            }

            (confirmed, flagged)
        })
        .reduce(
            || (0, Vec::new()),
            |(a, mut flagged), (b, more)| {
                flagged.extend(more);
                (a + b, flagged)
            },
        );

    // Slow pass: only the flagged pairs, in parallel.
    let slow_confirmed: usize = flagged
        .par_iter()
        .map(|flag| {
            let (check, file) = (checks[flag.check].as_ref(), &files[flag.file]);
            let mut findings = check.slow(file);
            debug_assert!(
                findings
                    .iter()
                    .all(|f| f.confidence == Confidence::Confirmed)
            );
            findings.retain(|f| !flag.reported.contains(f));
            report(&mut io::stdout().lock(), file, check, &mut findings)
        })
        .sum();

    let total = fast_confirmed + slow_confirmed;
    println!(
        "{} check(s) over {} file(s), {} slow pass(es), {} confirmed finding(s)",
        checks.len(),
        files.len(),
        flagged.len(),
        total
    );

    if total == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

/// Prints `findings` in line order and returns how many were confirmed.
fn report(
    out: &mut impl Write,
    file: &SourceFile,
    check: &dyn Check,
    findings: &mut [Finding],
) -> usize {
    findings.sort_by_key(|f| f.line);

    let mut confirmed = 0;
    for finding in findings.iter() {
        let label = match finding.confidence {
            Confidence::Confirmed => {
                confirmed += 1;
                "confirmed"
            }
            Confidence::Potential => "potential",
        };
        let _ = writeln!(
            out,
            "{}:{}: {} [{}, {label}]",
            file.path.display(),
            finding.line,
            finding.message,
            check.name()
        );
    }
    confirmed
}

/// Every readable UTF-8 source file under `roots` with a recognised extension.
fn collect_files(roots: &[PathBuf]) -> Vec<SourceFile> {
    roots
        .iter()
        .flat_map(|root| {
            WalkDir::new(root)
                .into_iter()
                .filter_entry(|entry| entry.depth() == 0 || !is_ignored_dir(entry.path()))
                .filter_map(Result::ok)
        })
        .filter(|entry| entry.file_type().is_file() && has_source_extension(entry.path()))
        .filter_map(|entry| {
            let path = entry.into_path();
            match std::fs::read_to_string(&path) {
                Ok(contents) => Some(SourceFile { path, contents }),
                Err(error) => {
                    eprintln!("skipping {}: {error}", path.display());
                    None
                }
            }
        })
        .collect()
}

fn is_ignored_dir(path: &Path) -> bool {
    path.is_dir()
        && path
            .file_name()
            .and_then(|name| name.to_str())
            .is_some_and(|name| IGNORED_DIRS.contains(&name))
}

fn has_source_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| EXTENSIONS.contains(&ext))
}
