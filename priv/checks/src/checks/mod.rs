//! The list of checks to run. Add a module here and push it onto `all`.

mod raw_html_tags;

use crate::check::Check;

pub fn all() -> Vec<Box<dyn Check>> {
    vec![Box::new(raw_html_tags::RawHtmlTags)]
}
