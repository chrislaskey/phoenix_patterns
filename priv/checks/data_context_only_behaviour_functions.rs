//! Data context only behaviour functions: a module that uses the data context behaviour
//! defines the callbacks it may override and nothing else. No other public
//! function, and no private one. Code a data context would need beyond that
//! belongs in another module that calls it.
//!
//! The callbacks are read from the behaviour module itself, once, in
//! `prepare`: the names and arities in its `defoverridable` list. A
//! definition counts by name and arity, so `def filter(query, key)` is not
//! an override of `filter/3`. Each function is reported once, on its first
//! clause. `def`, `defp`, `defmacro`, `defmacrop`, `defguard`, `defguardp`
//! and `defdelegate` all count. A definition inside a heredoc, such as an
//! example in a moduledoc, does not.
//!
//! Fast pass: the file contains `use` and the behaviour module's name.
//! Slow pass: confirms the `use` line, then reads every definition.
//!
//! Two config keys. `module`, given once: the behaviour module's file.
//! `paths`, given once per pattern: the files to check, matched against the
//! whole path from the project root.

use std::collections::HashSet;
use std::fs;
use std::sync::{LazyLock, OnceLock};

use globset::GlobSet;
use regex::Regex;

use crate::check::{Check, Config, File, Files, State, Violation, fast, glob_set, slow};

pub struct DataContextOnlyBehaviourFunctions {
    /// Set by `prepare`, read by `run`.
    behaviour: OnceLock<Behaviour>,
}

static DATA_CONTEXT_ONLY_BEHAVIOUR_FUNCTIONS: DataContextOnlyBehaviourFunctions =
    DataContextOnlyBehaviourFunctions::new();

pub const CHECK: &dyn Check = &DATA_CONTEXT_ONLY_BEHAVIOUR_FUNCTIONS;

/// `defmodule Name do`.
static MODULE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?m)^[ \t]*defmodule[ \t]+([A-Z][A-Za-z0-9_.]*)").unwrap());

/// The keyword list after `defoverridable`, which may span lines.
static DEFOVERRIDABLE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"defoverridable[ \t]+((?:[a-z_][A-Za-z0-9_]*[?!]?:\s*\d+\s*,?\s*)+)").unwrap()
});

/// One `name: arity` pair of the `defoverridable` list.
static PAIR: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"([a-z_][A-Za-z0-9_]*[?!]?):\s*(\d+)").unwrap());

/// A definition at the start of a line. Group 1 is the kind, group 2 the
/// name.
static DEFINITION: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?m)^[ \t]*(defp|defmacrop|defmacro|defguardp|defguard|defdelegate|def)[ \t]+([a-z_][A-Za-z0-9_]*[?!]?)",
    )
    .unwrap()
});

/// The behaviour module, as `prepare` read it.
#[derive(Debug)]
struct Behaviour {
    /// The module name, such as `App.Data.Context`.
    name: String,
    /// `use` then the module name, at the start of a line.
    use_line: Regex,
    /// Each overridable callback as `(name, arity)`.
    callbacks: HashSet<(String, usize)>,
    /// The files to check.
    paths: GlobSet,
}

impl DataContextOnlyBehaviourFunctions {
    const fn new() -> Self {
        Self {
            behaviour: OnceLock::new(),
        }
    }

    fn behaviour(&self) -> &Behaviour {
        self.behaviour
            .get()
            .expect("data_context_only_behaviour_functions runs prepare before run")
    }
}

impl Check for DataContextOnlyBehaviourFunctions {
    fn name(&self) -> &'static str {
        "data_context_only_behaviour_functions"
    }

    fn config_keys(&self) -> &'static [&'static str] {
        &["module", "paths"]
    }

    fn prepare(&self, config: &Config) -> Result<(), String> {
        // A second prepare, as in tests, keeps the first result.
        if self.behaviour.get().is_some() {
            return Ok(());
        }

        let path = config
            .one("module")
            .ok_or("set module to the file of the data context behaviour")?;
        let source =
            fs::read_to_string(path).map_err(|error| format!("could not read {path}: {error}"))?;
        let paths = glob_set("paths", &config.many("paths"))?;

        let _ = self.behaviour.set(Behaviour::parse(path, &source, paths)?);
        Ok(())
    }

    fn run(&self, state: &State, config: &Config) -> Result<Vec<Violation>, String> {
        let behaviour = self.behaviour();

        let files: Vec<&File> = state
            .files(config.scope())
            .with_extension(&["ex"])
            .into_iter()
            .filter(|file| behaviour.paths.is_match(&file.path))
            .collect();

        let suspects = fast(config, files, |file| {
            let contents = file.contents();
            contents.contains("use") && contents.contains(&behaviour.name)
        });

        let violations = slow(config, suspects, |file| {
            if !behaviour.use_line.is_match(file.contents()) {
                return Vec::new();
            }
            definitions(file.contents())
                .into_iter()
                .filter(|definition| !behaviour.allows(definition))
                .map(|definition| {
                    Violation::at(
                        file.line_of(definition.offset),
                        behaviour.message(&definition),
                    )
                })
                .collect()
        });

        Ok(state.in_scope(config.scope(), violations))
    }
}

impl Behaviour {
    /// Reads the module name and the overridable callbacks from `source`,
    /// the module at `path`.
    fn parse(path: &str, source: &str, paths: GlobSet) -> Result<Self, String> {
        let name = MODULE
            .captures(source)
            .map(|captures| captures[1].to_string())
            .ok_or_else(|| {
                format!("{path}: no defmodule found; set module to the behaviour's file")
            })?;

        let callbacks: HashSet<(String, usize)> = DEFOVERRIDABLE
            .captures_iter(source)
            .flat_map(|captures| {
                PAIR.captures_iter(captures.get(1).unwrap().as_str())
                    .map(|pair| (pair[1].to_string(), pair[2].parse().unwrap()))
                    .collect::<Vec<_>>()
            })
            .collect();

        if callbacks.is_empty() {
            return Err(format!(
                "{name} has no defoverridable list; set module to the behaviour's file"
            ));
        }

        let use_line = Regex::new(&format!(r"(?m)^[ \t]*use[ \t]+{}\b", regex::escape(&name)))
            .expect("module names are letters, digits, underscores and dots");

        Ok(Self {
            name,
            use_line,
            callbacks,
            paths,
        })
    }

    /// Whether `definition` overrides one of the callbacks.
    fn allows(&self, definition: &Definition) -> bool {
        definition.kind == "def"
            && self
                .callbacks
                .contains(&(definition.name.clone(), definition.arity))
    }

    fn message(&self, definition: &Definition) -> String {
        let Definition {
            kind, name, arity, ..
        } = definition;
        format!(
            "{kind} {name}/{arity} is not an overridable callback of {}; \
             a data context defines only those, move it to another module",
            self.name
        )
    }
}

/// One function, macro or guard defined in a file.
#[derive(Debug, PartialEq)]
struct Definition {
    /// `def`, `defp`, `defmacro` and so on.
    kind: String,
    name: String,
    arity: usize,
    /// The byte offset of the first clause.
    offset: usize,
}

/// Every definition in `contents` outside heredocs, once per kind, name and
/// arity, in the order of their first clause.
fn definitions(contents: &str) -> Vec<Definition> {
    let heredocs = heredoc_ranges(contents);
    let mut seen: HashSet<(String, String, usize)> = HashSet::new();
    let mut found = Vec::new();

    for captures in DEFINITION.captures_iter(contents) {
        let whole = captures.get(0).unwrap();
        if heredocs
            .iter()
            .any(|(start, end)| (*start..*end).contains(&whole.start()))
        {
            continue;
        }

        let kind = captures[1].to_string();
        let name = captures[2].to_string();
        let arity = arity(&contents[whole.end()..]);
        if seen.insert((kind.clone(), name.clone(), arity)) {
            found.push(Definition {
                kind,
                name,
                arity,
                offset: whole.start(),
            });
        }
    }
    found
}

/// The number of arguments in the list that starts `rest`, the text right
/// after a definition's name. No `(` there means none. Commas count only at
/// the top level of the list, outside strings and nested brackets. A list
/// with no closing `)` counts up to the end of the file.
fn arity(rest: &str) -> usize {
    let Some(rest) = rest.strip_prefix('(') else {
        return 0;
    };

    let mut depth = 0;
    let mut arguments = 0;
    let mut empty = true;
    let mut in_string = false;
    let mut previous = '(';
    let mut chars = rest.chars();

    while let Some(char) = chars.next() {
        if in_string {
            match char {
                '\\' => {
                    chars.next();
                }
                '"' => in_string = false,
                _ => {}
            }
            continue;
        }
        match char {
            '"' => in_string = true,
            '?' if !(previous.is_alphanumeric() || previous == '_') => {
                // A character literal such as `?,` or `?)`, not the end of
                // a name such as `valid?`.
                chars.next();
            }
            '(' | '[' | '{' => depth += 1,
            ')' | ']' | '}' if depth > 0 => depth -= 1,
            ')' => break,
            ',' if depth == 0 => arguments += 1,
            _ => {}
        }
        if !char.is_whitespace() {
            empty = false;
        }
        previous = char;
    }

    if empty { 0 } else { arguments + 1 }
}

/// The byte ranges of `contents` inside `"""` or `'''` heredocs, from the
/// opening delimiter to the closing one. A heredoc with no closing delimiter
/// runs to the end of the file.
fn heredoc_ranges(contents: &str) -> Vec<(usize, usize)> {
    let mut ranges = Vec::new();
    let mut from = 0;
    while let Some((start, delimiter)) = ["\"\"\"", "'''"]
        .iter()
        .filter_map(|delimiter| {
            contents[from..]
                .find(delimiter)
                .map(|found| (from + found, *delimiter))
        })
        .min()
    {
        let body = start + delimiter.len();
        match contents[body..].find(delimiter) {
            Some(length) => {
                let end = body + length + delimiter.len();
                ranges.push((start, end));
                from = end;
            }
            None => {
                ranges.push((start, contents.len()));
                break;
            }
        }
    }
    ranges
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::check::Scope;
    use crate::check::testing::{config, run, scoped, state};

    /// A behaviour with a few overridable callbacks, one of them on its own
    /// line, and one function that is not overridable.
    const BEHAVIOUR_SOURCE: &str = "\
defmodule App.Data.Context do
  defmacro __using__(opts \\\\ []) do
    quote do
      def schema, do: Keyword.get(unquote(opts), :schema)

      defoverridable list: 1,
                     filter: 3,
                     get: 2,
                     delete: 1
    end
  end
end
";

    /// A check prepared from `BEHAVIOUR_SOURCE` for files under `schemas`,
    /// so `prepare` has nothing to read.
    fn check() -> DataContextOnlyBehaviourFunctions {
        let check = DataContextOnlyBehaviourFunctions::new();
        let paths = glob_set("paths", &["lib/schemas/**"]).unwrap();
        check
            .behaviour
            .set(Behaviour::parse("context.ex", BEHAVIOUR_SOURCE, paths).unwrap())
            .unwrap();
        check
    }

    #[test]
    fn reads_the_module_name_and_the_overridable_callbacks() {
        let paths = glob_set("paths", &["*"]).unwrap();
        let behaviour = Behaviour::parse("context.ex", BEHAVIOUR_SOURCE, paths).unwrap();
        assert_eq!(behaviour.name, "App.Data.Context");

        let mut callbacks: Vec<_> = behaviour.callbacks.into_iter().collect();
        callbacks.sort();
        assert_eq!(
            callbacks,
            vec![
                ("delete".to_string(), 1),
                ("filter".to_string(), 3),
                ("get".to_string(), 2),
                ("list".to_string(), 1),
            ]
        );
    }

    #[test]
    fn a_module_without_a_name_or_a_defoverridable_list_is_refused() {
        let paths = || glob_set("paths", &["*"]).unwrap();
        let error = Behaviour::parse("context.ex", "def list(a)", paths()).unwrap_err();
        assert_eq!(
            error,
            "context.ex: no defmodule found; set module to the behaviour's file"
        );

        let error = Behaviour::parse("context.ex", "defmodule A do\nend\n", paths()).unwrap_err();
        assert_eq!(
            error,
            "A has no defoverridable list; set module to the behaviour's file"
        );
    }

    #[test]
    fn overrides_are_allowed_and_everything_else_is_reported() {
        let check = check();
        let state = state()
            .file(
                "lib/schemas/users.ex",
                "\
defmodule App.Data.Users do
  @moduledoc \"\"\"
  Override like this:

      def helper(query), do: query
  \"\"\"

  use App.Data.Context, schema: App.Data.User

  @limit 10

  def filter(query, :name, value) when is_binary(value) do
    where(query, name: ^value)
  end

  def filter(query, key, value), do: super(query, key, value)

  def get(id, options \\\\ []), do: super(id, options)

  def filter(query, key), do: query

  def active(query) do
    query
  end

  def schema, do: App.Data.User

  defp helper(%{a: 1, b: 2}, [x, y], \"a,b)\", ?,), do: x

  defmacro thing(ast), do: ast
end
",
            )
            .build();
        assert_eq!(
            run(&check, &state, &config(&check, &[])),
            vec![
                "lib/schemas/users.ex:20: def filter/2 is not an overridable callback of App.Data.Context; a data context defines only those, move it to another module",
                "lib/schemas/users.ex:22: def active/1 is not an overridable callback of App.Data.Context; a data context defines only those, move it to another module",
                "lib/schemas/users.ex:26: def schema/0 is not an overridable callback of App.Data.Context; a data context defines only those, move it to another module",
                "lib/schemas/users.ex:28: defp helper/4 is not an overridable callback of App.Data.Context; a data context defines only those, move it to another module",
                "lib/schemas/users.ex:30: defmacro thing/1 is not an overridable callback of App.Data.Context; a data context defines only those, move it to another module",
            ]
        );
    }

    #[test]
    fn a_private_function_named_like_a_callback_is_reported() {
        let check = check();
        let state = state()
            .file(
                "lib/schemas/users.ex",
                "use App.Data.Context\n\ndefp list(options), do: options\n",
            )
            .build();
        assert_eq!(
            run(&check, &state, &config(&check, &[])),
            vec![
                "lib/schemas/users.ex:3: defp list/1 is not an overridable callback of App.Data.Context; a data context defines only those, move it to another module",
            ]
        );
    }

    #[test]
    fn only_files_in_paths_that_use_the_behaviour_are_checked() {
        let check = check();
        let state = state()
            .file(
                "lib/schemas/users.ex",
                "use App.Data.Context\ndef a, do: 1\n",
            )
            .file("lib/schemas/user.ex", "use Ecto.Schema\ndef a, do: 1\n")
            .file(
                "lib/schemas/other.ex",
                "# use App.Data.Context\nalias App.Data.Context\ndef a, do: 1\n",
            )
            .file("lib/accounts.ex", "use App.Data.Context\ndef a, do: 1\n")
            .file(
                "lib/schemas/users.exs",
                "use App.Data.Context\ndef a, do: 1\n",
            )
            .build();
        assert_eq!(
            run(&check, &state, &config(&check, &[])),
            vec![
                "lib/schemas/users.ex:2: def a/0 is not an overridable callback of App.Data.Context; a data context defines only those, move it to another module",
            ]
        );
    }

    #[test]
    fn the_changed_scope_reports_changed_lines_only() {
        let check = check();
        let state = state()
            .changed(
                "lib/schemas/users.ex",
                "use App.Data.Context\ndef a, do: 1\ndef b, do: 1\n",
                &[3],
            )
            .build();
        assert_eq!(
            run(&check, &state, &scoped(&check, Scope::Changed, &[])),
            vec![
                "lib/schemas/users.ex:3: def b/0 is not an overridable callback of App.Data.Context; a data context defines only those, move it to another module",
            ]
        );
    }

    #[test]
    fn arity_counts_top_level_arguments() {
        assert_eq!(arity(", do: 1"), 0);
        assert_eq!(arity("() do"), 0);
        assert_eq!(arity("(a) do"), 1);
        assert_eq!(arity("(a, b \\\\ []) when is_list(b) do"), 2);
        assert_eq!(arity("(%{a: 1, b: 2}, [c, d], {e, f}) do"), 3);
        assert_eq!(arity("(\"a, \\\"b)\", ?,, ?)) do"), 3);
        assert_eq!(arity("(\n  a,\n  b\n) do"), 2);
        assert_eq!(arity("(a, b \\\\ valid?(a)) do"), 2);
    }

    #[test]
    fn heredocs_run_between_their_delimiters() {
        let contents = "a \"\"\"\nb\n\"\"\" c '''\nd";
        assert_eq!(heredoc_ranges(contents), vec![(2, 11), (14, 19)]);
    }

    #[test]
    fn prepare_reads_the_module_and_refuses_bad_config() {
        let dir = std::env::temp_dir().join(format!("data-context-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let module = dir.join("context.ex");
        std::fs::write(&module, BEHAVIOUR_SOURCE).unwrap();
        let module = module.to_str().unwrap();

        let check = DataContextOnlyBehaviourFunctions::new();
        let error = check
            .prepare(&config(&check, &[("paths", "lib/**")]))
            .unwrap_err();
        assert_eq!(
            error,
            "set module to the file of the data context behaviour"
        );

        let error = check
            .prepare(&config(
                &check,
                &[("module", "/no/such/file.ex"), ("paths", "lib/**")],
            ))
            .unwrap_err();
        assert!(error.starts_with("could not read /no/such/file.ex"));

        let error = check
            .prepare(&config(&check, &[("module", module)]))
            .unwrap_err();
        assert_eq!(error, "set paths to at least one path pattern");

        let config = config(&check, &[("module", module), ("paths", "lib/**")]);
        let state = state()
            .file(
                "lib/users.ex",
                "use App.Data.Context\ndef get(id, opts), do: 1\n",
            )
            .build();
        assert_eq!(run(&check, &state, &config), Vec::<String>::new());

        let _ = std::fs::remove_dir_all(&dir);
    }
}
