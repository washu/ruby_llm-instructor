## [Unreleased]

## [0.2.0] - 2026-06-05

### Added
- `RubyLLM::Instructor::Utils` module — `dry_contract?` is now a shared helper
  instead of a private method copy-pasted in two places.
- Positional `Struct` support — `Struct.new(:x, :y)` (without `keyword_init: true`)
  is now hydrated correctly via positional arguments.
- `mode:` parameter validation — passing an unknown mode now raises `ArgumentError`
  immediately with a clear message instead of silently falling through.

### Changed
- **Breaking**: `ValidationError` is now raised (instead of `RuntimeError`) when all
  retries are exhausted. Update any `rescue RuntimeError` around `#chat` calls to
  `rescue RubyLLM::Instructor::ValidationError`.
- Retry prompt now includes the original task: `"Original task: …\n\nYour previous
  response failed validation: …"`, giving the model full context on each retry instead
  of only the error message.
- `ruby_llm-schema` runtime dependency tightened to `>= 0.4.0, < 2` to guard against
  unexpected breaking major-version upgrades.
- Gemspec now derives `version` from `RubyLLM::Instructor::VERSION` constant.
- Added `homepage`, `source_code_uri`, `changelog_uri`, and `bug_tracker_uri` to
  gemspec metadata.

## [0.1.0] - 2026-06-03

- Initial release
