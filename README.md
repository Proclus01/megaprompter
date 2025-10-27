# Megaprompter, MegaDiagnose, and MegaTest

Three companion CLIs for working with real project trees:

- megaprompt: Generate a single, copy-paste-friendly megaprompt from your source code and essential configs (tests included).
- megadiagnose: Scan your project with language-appropriate tools, collect errors/warnings, and emit an XML/JSON diagnostic summary plus a ready-to-use fix prompt.
- megatest: Analyze your codebase to propose a comprehensive test plan (smoke/unit/integration/e2e) with edge cases and fuzz inputs. It produces XML/JSON plus a “write these tests” prompt and a MEGATEST_* artifact.

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

- Safety first: refuses to run outside a code project (override with `--force`).
- Smart detection: identifies TypeScript/JS, Swift, Python, Go, Rust, Java/Kotlin, C/C++, C#, PHP, Ruby, Terraform, etc.
- Language-aware rules: prefers `.ts/.tsx` over `.js/.jsx` when TypeScript is present.
- Pruning: skips vendor, build, and cache directories for speed and relevance. You can also pass your own prunes with `--ignore`.
- Output: one blob with each file wrapped as a tag of its relative path and the content in `CDATA`.
- Persistence + Clipboard: writes `.MEGAPROMPT_YYYYMMDD_HHMMSS` (hidden dotfile) and copies the same text to your clipboard.

### Usage (examples)

```bash
megaprompt .
megaprompt packages/app
megaprompt . --ignore data --ignore docs/generated/**
megaprompt . --dry-run --show-summary
megaprompt . --force
megaprompt . --max-file-bytes 500000
```

---

## MegaDiagnose (megadiagnose)

Scan your project, run language‑appropriate compilers/checkers, capture errors/warnings, and emit a compact XML/JSON diagnostic summary plus a ready‑to‑use fix prompt for LLMs. Writes a single-file artifact in your project directory that bundles the XML, JSON, and the fix prompt.

- Auto-detects project languages (reuses Megaprompter detection).
- Executes relevant tools when available:
  - Swift (SwiftPM): `swift build`
  - TypeScript: `npx -y tsc -p . --noEmit`
  - JavaScript-only projects: try `npx -y tsc --allowJs --checkJs --noEmit`, then fallback to `npx -y eslint -f unix .`, else `npm run -s build`
  - Go: deep scan across ALL packages (`go list ./...` + `go build -gcflags=all=-e <pkg>`)
  - Rust: `cargo check --color never`
  - Python: `python3 -m py_compile` on each `.py` file
  - Java: `mvn -q -DskipTests compile` or `gradle -q classes`
- Outputs:
  - XML diagnostics (to stdout by default; configurable via `--xml-out`)
  - JSON diagnostics (`--json-out`)
  - Fix prompt (`--prompt-out`)
  - Artifact: `MEGADIAG_YYYYMMDD_HHMMSS` (or hidden `.MEGADIAG_*`)
  - Convenience symlink: `MEGADIAG_latest` (or `.MEGADIAG_latest`)

### Usage

```bash
megadiagnose .
megadiagnose . --artifact-hidden
megadiagnose . --artifact-dir artifacts/
megadiagnose . --ignore data --ignore docs/generated/**
megadiagnose . --xml-out diag.xml --json-out diag.json --prompt-out fix_prompt.txt
megadiagnose . --timeout-seconds 180
megadiagnose . --force
```

---

## MegaTest (megatest)

Analyze your repo and produce a comprehensive, language-aware test plan. Identifies testable subjects (functions/methods/classes/endpoints/entrypoints), infers I/O and complexity risk, and proposes concrete scenarios per level: smoke, unit, integration, end-to-end. It does not write tests; it outputs an actionable plan and a “write these tests” prompt.

- Reuses project detection and scanning rules (same ignores).
- Fast, portable heuristics:
  - TypeScript/JavaScript: exported functions/classes (incl. arrow/assigned), Express/Fastify routes
  - Python: functions/classes, Flask/FastAPI decorators
  - Go: functions, http.HandleFunc/gin routes
  - Rust: pub fn, actix/rocket route macros
  - Swift: functions/classes/structs/enums/inits
  - Java: classes/interfaces/methods, Spring @GetMapping/@PostMapping/etc.
  - Kotlin: classes/objects/data classes/fun, Spring annotations, basic Ktor DSL routes
- Risk & I/O inference:
  - Branching and concurrency hints
  - FS/network/db/env access
- Suggests:
  - Unit test fuzz/edge inputs per parameter hints (timeouts/ports/paths/urls/emails, etc.)
  - Integration tests for I/O and concurrency
  - Smoke tests for entrypoints
  - E2E tests for detected endpoints
- Outputs:
  - XML test plan (to stdout by default; `--xml-out` to file)
  - JSON test plan (`--json-out`)
  - A test prompt (`--prompt-out`)
  - Artifact: `MEGATEST_YYYYMMDD_HHMMSS` (or hidden `.MEGATEST_*`)
  - Convenience symlink: `MEGATEST_latest` (or `.MEGATEST_latest`)

### Usage

```bash
# Visible artifact and XML to stdout
megatest .

# Hidden artifact and separate prompt file
megatest . --artifact-hidden --prompt-out test_prompt.txt

# Only certain levels (subset of smoke,unit,integration,e2e)
megatest . --levels unit,integration

# Ignore directories/files by name or glob (repeatable)
megatest . --ignore data --ignore docs/generated/** --ignore .cache/**

# Save outputs to files and cap file sizes for scanning/analysis
megatest . --xml-out plan.xml --json-out plan.json --max-file-bytes 800000 --max-analyze-bytes 120000
```

#### Command Options

```
USAGE: megatest [<path>] [--force] [--limit-subjects <int>] [--levels <csv>] [--xml-out <path>] [--json-out <path>] [--prompt-out <path>] [--show-summary|--no-show-summary] [--artifact-hidden] [--artifact-dir <path>] [--ignore <name-or-glob> ...] [--max-file-bytes <int>] [--max-analyze-bytes <int>]

ARGUMENTS:
  <path>                 Target directory ('.' by default). Accepts relative or absolute paths.

OPTIONS:
  --force                Force run even if the directory does not look like a code project.
  --limit-subjects       Limit number of subjects analyzed (default: 500).
  --levels               Comma-separated levels to include: smoke,unit,integration,e2e (default: all).
  --xml-out              Write XML output to this file (default: stdout).
  --json-out             Write JSON output to this file.
  --prompt-out           Write test prompt text to this file.
  --show-summary         Print a brief summary to stderr (default: on).
  --no-show-summary      Disable the summary.
  --artifact-hidden      Write artifact as a hidden dotfile (.MEGATEST_*). Default is visible (MEGATEST_*).
  --artifact-dir         Directory where the MEGATEST_* artifact is written (default: the target path).
  --ignore               Directory names or glob paths to ignore (repeatable).
                         Examples: --ignore data --ignore docs/generated/**
                         Short aliases: -I, -i
  --max-file-bytes       Skip files larger than this many bytes during scanning (default: 1500000).
  --max-analyze-bytes    Analyze at most this many bytes of each file for heuristics (default: 200000).
  -h, --help             Show help information.
```

### What it Writes

- Artifact file in your target directory (or `--artifact-dir`):
  - Visible: `MEGATEST_YYYYMMDD_HHMMSS`
  - Hidden: `.MEGATEST_YYYYMMDD_HHMMSS` (if `--artifact-hidden`)
- The artifact is a pseudo‑XML envelope that embeds:
  - `<xml>`: the XML test plan summary
  - `<json>`: the same plan in JSON
  - `<test_prompt>`: a short, actionable prompt for LLMs to produce tests (respects `--levels`)
- A convenience symlink to the most recent artifact:
  - `MEGATEST_latest` (visible) or `.MEGATEST_latest` (hidden)

Note for Windows users:
- Creating symlinks for `*_latest` may require Developer Mode or admin privileges.

---

## Safety Features (all tools)

- Refuse to run if the target directory doesn’t look like a code project (use `--force` to override).
- Skip oversized files by default (megaprompt/megatest `--max-file-bytes`) to avoid huge artifacts.
- Skip `.env*` and common secret/binary extensions in megaprompt’s selection rules.
- Tool invocations (megadiagnose) are timed out per-tool.

---

## Development

```bash
swift build
swift test
```

Run without installing:

```bash
swift run megaprompt .
swift run megadiagnose .
swift run megatest .
```

---

## Uninstall

```bash
sudo rm -f /usr/local/bin/megaprompt
sudo rm -f /usr/local/bin/megadiagnose
sudo rm -f /usr/local/bin/megatest
```

---

## License

MIT (see `LICENSE` if present).
