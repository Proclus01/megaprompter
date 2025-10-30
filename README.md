# Megaprompter, MegaDiagnose, MegaTest, and MegaDoc

Three companion CLIs for working with real project trees, plus a documentation-oriented agent feed:

- megaprompt: Generate a single, copy-paste-friendly megaprompt from your source code and essential configs (tests included).
- megadiagnose: Scan your project with language-appropriate tools, collect errors/warnings, and emit an XML/JSON diagnostic summary plus a ready-to-use fix prompt.
- megatest: Analyze your codebase to propose a comprehensive test plan (smoke/unit/integration/e2e/regression) with edge cases and fuzz inputs. It also inspects existing tests and marks coverage per subject:
  - green = DONE (adequate tests found; suggestions suppressed)
  - yellow = PARTIAL (some coverage; suggestions retained)
  - red = MISSING (no coverage; full suggestions)
  The artifact includes evidence of where tests live.
- megadoc: Build a documentation artifact for agents. From local code it emits an ASCII directory tree, an import/dependency graph, a purpose summary; from URIs it fetches/crawls content and summarizes. Outputs an XML/JSON + prompt artifact (MEGADOC_*).

All tools are safe-by-default, language-aware, and tuned for LLM usage and code reviews.

---

## Build & Install

```bash
swift package resolve
swift build -c release
```

Add the executables to your PATH (macOS examples):

```bash
sudo ln -sf "$PWD/.build/release/megaprompt" /usr/local/bin/megaprompt
sudo ln -sf "$PWD/.build/release/megadiagnose" /usr/local/bin/megadiagnose
sudo ln -sf "$PWD/.build/release/megatest" /usr/local/bin/megatest
sudo ln -sf "$PWD/.build/release/megadoc" /usr/local/bin/megadoc
```

Re-run with sudo if you hit “Permission denied”. To update later, rebuild and re-link.

---

## What counts as a “project”?

The detector marks a directory as a “code project” if either:
- Any recognized marker exists (e.g., Package.swift, package.json, pyproject.toml, go.mod, Cargo.toml, pom.xml, etc.), or
- At least 8 recognizable source files are present (based on known extensions).

All CLIs refuse to run outside a detected project unless you pass --force.

---

## Megaprompter (megaprompt)

Generate a single XML-like megaprompt containing real source files and essential configs (tests included) — perfect for pasting into LLMs or code review tools.

See CLI help for options like --ignore, --dry-run, --max-file-bytes.

---

## MegaDiagnose (megadiagnose)

Scan your project, run language‑appropriate compilers/checkers, capture errors/warnings, and emit a compact XML/JSON diagnostic summary plus a ready‑to‑use fix prompt for LLMs. Writes a single-file artifact in your project directory.

New in this version:
- --include-tests compiles/analyzes test sources without running them:
  - Swift: swift build --build-tests
  - Rust: cargo test --no-run
  - Go: go test -c -o /dev/null per package
  - Java (Maven): mvn -DskipTests test-compile
  - Java (Gradle): gradle testClasses
  - JS/TS: additional eslint -f unix pass over common test globs
- All existing --ignore rules apply to test files too.

Examples:

```bash
megadiagnose .
megadiagnose . --include-tests
megadiagnose . --ignore build --ignore docs/generated/**
megadiagnose . --xml-out diag.xml --json-out diag.json --prompt-out fix_prompt.txt
```

---

## MegaTest (megatest)

Analyze your repo and produce a comprehensive, language-aware test plan. Identifies testable subjects, infers I/O and complexity risk, and proposes concrete scenarios per level: smoke, unit, integration, end-to-end, regression.

New in this version:
- Coverage-aware suggestions. Existing tests are analyzed and subjects are flagged:
  - green = DONE (adequate tests found) → non-regression scenarios are suppressed. Artifact shows evidence (file paths) as DONE.
  - yellow = PARTIAL (some coverage) → suggestions kept, prioritized.
  - red = MISSING (no coverage) → full suggestions.
- Regression scenarios: opt-in via git diff. For files changed since a ref or across a range, impacted subjects get a [regression] scenario that is not suppressed even if coverage is green.

Usage examples:

```bash
megatest .
megatest . --levels unit,integration
megatest . --ignore data --ignore docs/generated/**
megatest . --xml-out plan.xml --json-out plan.json --prompt-out test_prompt.txt
megatest . --max-file-bytes 800000 --max-analyze-bytes 120000
# Regression-focused runs
megatest . --regression-since origin/main
megatest . --regression-range HEAD~3..HEAD --levels unit,regression
```

Regression flags:
- --regression-since <git-ref>  Compare <ref>..HEAD; add regression scenarios for impacted subjects.
- --regression-range A..B       Compare explicit range; add regression scenarios for impacted subjects.
- --no-regression               Disable regression scenarios.

Notes:
- Requires git in PATH and a git repository; otherwise a warning is logged and the run continues without regression scenarios.

---

## MegaDoc (megadoc)

Produce a documentation artifact for agents and reviewers.

Two modes:

- Local analysis (code → structure + purpose)
  - Builds an ASCII directory tree (prunes build/vendor/caches)
  - Extracts imports and draws an ASCII dependency graph
  - Summarizes likely purpose from README and high-signal code hints
  - Emits XML/JSON + a ready-to-use prompt; writes MEGADOC_* in the run directory

- Fetch mode (URI(s) → fetched doc previews)
  - Fetches local paths (file://, absolute) or HTTP(S) with optional depth and domain allow-list
  - Crawls same-domain links up to --crawl-depth
  - Summarizes fetched docs and embeds previews

Examples:

```bash
# Local create
megadoc --create .
megadoc --create . --ignore build --ignore node_modules --tree-depth 5 \
  --xml-out doc.xml --json-out doc.json --prompt-out doc_prompt.txt

# Fetch docs
megadoc --get https://learn.microsoft.com/azure --crawl-depth 2 --allow-domain learn.microsoft.com
megadoc --get https://platform.openai.com/docs/introduction --allow-domain platform.openai.com
megadoc --get https://developer.squareup.com/docs --allow-domain developer.squareup.com
megadoc --get https://docs.stripe.com --allow-domain docs.stripe.com
megadoc --get ./docs --get README.md
```

Safety defaults:
- Local runs require project detection unless --force is provided.
- HTTP crawling is limited by --allow-domain and --crawl-depth.

---
