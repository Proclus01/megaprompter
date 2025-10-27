# Megaprompter, MegaDiagnose, and MegaTest

Three companion CLIs for working with real project trees:

- megaprompt: Generate a single, copy-paste-friendly megaprompt from your source code and essential configs (tests included).
- megadiagnose: Scan your project with language-appropriate tools, collect errors/warnings, and emit an XML/JSON diagnostic summary plus a ready-to-use fix prompt.
- megatest: Analyze your codebase to propose a comprehensive test plan (smoke/unit/integration/e2e) with edge cases and fuzz inputs. It produces XML/JSON plus a “write these tests” prompt and a MEGATEST_* artifact.

All tools are safe-by-default, language-aware, and tuned for LLM usage and code reviews.

---

## Build & Install

```bash
# Clone this repository, then:
swift package resolve
swift build -c release
```

Add the executables to your PATH (macOS examples):

```bash
# If /usr/local/bin requires elevated permissions:
sudo ln -sf "$PWD/.build/release/megaprompt" /usr/local/bin/megaprompt
sudo ln -sf "$PWD/.build/release/megadiagnose" /usr/local/bin/megadiagnose
sudo ln -sf "$PWD/.build/release/megatest" /usr/local/bin/megatest
```

If you saw “Permission denied” while linking, re-run with sudo as above.  
To update later, rebuild and re-link.

---

## What counts as a “project”?

The detector marks a directory as a “code project” if either:
- Any recognized marker exists (e.g., Package.swift, package.json, pyproject.toml, go.mod, Cargo.toml, pom.xml, etc.), or
- At least 8 recognizable source files are present (based on known extensions).

All CLIs refuse to run outside a detected project unless you pass --force.

---

## Megaprompter (megaprompt)

Generate a single XML-like megaprompt containing the real source files and essential configs from your project (tests included) — perfect for pasting into LLMs or code review tools.

- Safety first: refuses to run outside a code project (override with `--force`).
- Smart detection: identifies TypeScript/JS, Swift, Python, Go, Rust, Java/Kotlin, C/C++, C#, PHP, Ruby, Terraform, etc.
- Language-aware rules: prefers `.ts/.tsx` over `.js/.jsx` when TypeScript is present.
- Pruning: skips vendor, build, and cache directories for speed and relevance. You can also pass your own prunes with `--ignore`.
- Output: one blob with each file wrapped as a tag of its relative path and the content in `CDATA`.
- Persistence + Clipboard: writes `.MEGAPROMPT_YYYYMMDD_HHMMSS` (hidden dotfile) and copies the same text to your clipboard.

### Usage

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

A companion CLI that scans your project, runs language‑appropriate compilers/checkers, captures errors/warnings, and emits a compact XML diagnostic summary plus a ready‑to‑use fix prompt for LLMs. It also writes a single-file artifact to your project directory that bundles the XML, JSON, and the fix prompt.

- Automatic detection of project languages (reuses Megaprompter detector).
- Executes relevant tools when available:
  - Swift (SwiftPM): `swift build`
  - TypeScript: `npx -y tsc -p . --noEmit`
  - JavaScript-only projects: try `npx -y tsc --allowJs --checkJs --noEmit`, then fallback to `npx -y eslint -f unix .`, else `npm run -s build`
  - Go: deep scan across ALL packages (`go list ./...`; `go build -gcflags=all=-e <pkg>`)
  - Rust: `cargo check --color never`
  - Python: `python3 -m py_compile` on each `.py` file
  - Java: `mvn -q -DskipTests compile` or `gradle -q classes`
- Outputs:
  - XML diagnostics (to stdout by default; configurable via `--xml-out`)
  - JSON diagnostics (`--json-out`)
  - Fix prompt (`--prompt-out`)
  - Artifact in the target directory: `MEGADIAG_YYYYMMDD_HHMMSS` (visible by default; `--artifact-hidden` for hidden)
  - Convenience symlink updated on each run: `MEGADIAG_latest` (or `.MEGADIAG_latest`)

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

Analyze your repo and produce a comprehensive, language-aware test plan. It identifies testable subjects (functions/methods/classes/endpoints/entrypoints), infers I/O and complexity risk, and proposes concrete scenarios per level: smoke, unit, integration, and end-to-end. It does not write tests; it outputs an actionable plan and a “write these tests” prompt.

- Reuses project detection and scanning rules (same ignores).
- Lightweight static heuristics (regex-based, fast) for:
  - TypeScript/JavaScript: exported functions/classes, Express routes
  - Python: functions/classes, Flask/FastAPI decorators
  - Go: functions, http.HandleFunc/gin routes
  - Rust: pub fn, actix/rocket route macros
  - Swift: functions/classes/structs/enums
  - Java: public classes and methods, Spring @GetMapping/@PostMapping/etc.
- Risk & I/O inference:
  - Branching, concurrency hints
  - FS/network/db/env access
- Suggests:
  - Unit test fuzz/edge inputs per parameter hints
  - Integration tests for I/O and concurrency
  - Smoke tests for entrypoints
  - E2E tests for detected endpoints
- Outputs:
  - XML test plan (to stdout by default; `--xml-out` to file)
  - JSON test plan (`--json-out`)
  - A test prompt (`--prompt-out`)
  - Artifact in the target directory: `MEGATEST_YYYYMMDD_HHMMSS` (or hidden `.MEGATEST_*`)
  - Convenience symlink: `MEGATEST_latest` (or `.MEGATEST_latest`)

### Usage

```bash
# Write a visible MEGATEST_* artifact and print XML to stdout
megatest .

# Hidden artifact and separate prompt file
megatest . --artifact-hidden --prompt-out test_prompt.txt

# Only generate certain levels (subset of smoke,unit,integration,e2e)
megatest . --levels unit,integration

# Ignore directories/files by name or glob (repeatable)
megatest . --ignore data --ignore docs/generated/** --ignore .cache/**

# Save outputs to files in addition to the artifact
megatest . --xml-out plan.xml --json-out plan.json
```

#### Command Options

```
USAGE: megatest [<path>] [--force] [--limit-subjects <int>] [--levels <csv>] [--xml-out <path>] [--json-out <path>] [--prompt-out <path>] [--show-summary|--no-show-summary] [--artifact-hidden] [--artifact-dir <path>] [--ignore <name-or-glob> ...]

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
  -h, --help             Show help information.
```

### What it Writes

- A single artifact file in your target directory (or `--artifact-dir`):
  - Visible: `MEGATEST_YYYYMMDD_HHMMSS`
  - Hidden: `.MEGATEST_YYYYMMDD_HHMMSS` (if `--artifact-hidden` is used)
- The artifact is a pseudo‑XML envelope that embeds:
  - `<xml>`: the XML test plan summary and a test_prompt section.
  - `<json>`: the same plan in JSON.
  - `<test_prompt>`: a short, actionable prompt for LLMs to produce tests.
- A convenience symlink to the most recent artifact:
  - `MEGATEST_latest` (visible) or `.MEGATEST_latest` (hidden)

---

## Safety Features (all tools)

- Refuse to run if the target directory doesn’t look like a code project (use `--force` to override).
- Skip oversized files by default (megaprompt `--max-file-bytes`) to avoid grabbing huge artifacts.
- Skip `.env*` and common secret/binary extensions in megaprompt selection rules.
- Tool invocations (megadiagnose) are timed out per-tool.

---

## Troubleshooting

- Permission denied while linking  
  Use sudo when linking into system paths:

  ```bash
  sudo ln -sf "$PWD/.build/release/megaprompt" /usr/local/bin/megaprompt
  sudo ln -sf "$PWD/.build/release/megadiagnose" /usr/local/bin/megadiagnose
  sudo ln -sf "$PWD/.build/release/megatest" /usr/local/bin/megatest
  ```

  Alternatively, link into a user‑writable PATH directory (e.g., `~/bin`) and ensure it’s on your PATH.

- Clipboard didn’t copy (megaprompt)  
  The tool tries `pbcopy` → `wl-copy` → `xclip` → `xsel` → (Windows) `clip`. If none are present, it still writes the `.MEGAPROMPT_*` file. Install one of those tools or copy from the file manually.

- Too many files included/excluded (megaprompt)  
  Use `--dry-run --show-summary` to see the exact file list. If you need different behavior, adjust `Sources/MegaprompterCore/Rules.swift` or exclude specific directories/paths at runtime with `--ignore`.

---

## Development

Build and test:

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
# (or wherever you linked them)
```

---

## License

MIT (see `LICENSE` if present).
