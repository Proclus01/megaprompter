# Megaprompter and MegaDiagnose

Two companion CLIs for working with real project trees:

- megaprompt: Generate a single, copy-paste-friendly megaprompt from your source code and essential configs (tests included).
- megadiagnose: Scan your project with language-appropriate tools, collect errors/warnings, and emit an XML/JSON diagnostic summary plus a ready-to-use fix prompt.

Both tools are safe-by-default, language-aware, and tuned for LLM usage and code reviews.

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
```

If you saw “Permission denied” while linking, re-run with sudo as above.  
To update later, rebuild and re-link.

---

## What counts as a “project”?

The detector marks a directory as a “code project” if either:
- Any recognized marker exists (e.g., Package.swift, package.json, pyproject.toml, go.mod, Cargo.toml, pom.xml, etc.), or
- At least 8 recognizable source files are present (based on known extensions).

Both CLIs refuse to run outside a detected project unless you pass --force.

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

From a project root:

```bash
megaprompt .
```

Target only a subdirectory:

```bash
megaprompt packages/app
megaprompt foo/bar
```

Ignore directories by name or glob/path (repeatable):

```bash
# Ignore all directories named "data" anywhere in the tree
megaprompt . --ignore data

# Ignore by glob/path (relative to the target root)
megaprompt . --ignore docs/generated/**
megaprompt . -I .cache/**     # also supports a short -I (and -i)

# Combine multiple ignores
megaprompt . --ignore screenshots --ignore assets/** --ignore tmp
```

Dry run & show summary (no write/clipboard):

```bash
megaprompt . --dry-run --show-summary
```

Force run in a directory that wasn’t auto-detected as a project:

```bash
megaprompt . --force
```

Skip very large files (bytes):

```bash
megaprompt . --max-file-bytes 500000
```

#### Command Options

```
USAGE: megaprompt [<path>] [--force] [--max-file-bytes <int>] [--ignore <name-or-glob> ...] [--dry-run] [--show-summary]

ARGUMENTS:
  <path>                 Target directory ('.' by default). Accepts relative or absolute paths.

OPTIONS:
  --force                Force run even if the directory does not look like a code project.
  --max-file-bytes       Skip files larger than this many bytes (default: 1500000).
  --ignore               Directory names or glob paths to ignore (repeatable).
                         Examples: --ignore data --ignore docs/generated/** --ignore .cache/**
                         Short alias: -I (also accepts -i)
  --dry-run              Only show what would be included; do not write or copy.
  --show-summary         Print a summary of detected project types and included files.
  -h, --help             Show help information.
```

### What it Outputs

Megaprompter writes a file named `.MEGAPROMPT_YYYYMMDD_HHMMSS` to the target directory and attempts to copy the same text to your clipboard.

Snippet (example):

```xml
<context>
<src/index.ts>
<![CDATA[
import { createApp } from 'vue'
import App from './App.vue'
createApp(App).mount('#app')
]]>
</src/index.ts>

<.github/workflows/ci.yml>
<![CDATA[
name: CI
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps: ...
]]>
</.github/workflows/ci.yml>
</context>
```

Tag names are the relative file paths. It’s intentionally pseudo-XML to keep things copy‑paste friendly for LLMs.

### How It Decides What To Include

- Language detection: Looks for canonical markers (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `Package.swift`, etc.) and/or ≥8 recognizable source files.
- TypeScript preference: If TypeScript is present, `.js`/`.jsx` are excluded; `.mjs`/`.cjs` (Node configs) remain allowed.
- Always include certain config files by exact name (e.g., `package.json`, `pyproject.toml`, `Dockerfile`, `Makefile`, `tsconfig.json`, `eslint`/`prettier` configs).
- Always include GitHub Actions/Actions YAML:
  - `.github/workflows/*.yml|yaml`
  - `.github/actions/**/*.yml|yaml`
- Treat tests as code: files/folders matching common patterns (`*.test.*`, `*.spec.*`, `__tests__`, `tests`, `spec`, etc.).
- Pruned directories (partial list): `node_modules`, `.git`, `.next`, `dist`, `build`, `out`, `target`, `bin`, `obj`, `vendor`, `.terraform`, `.gradle`, `.idea`, `.vscode`, `__pycache__`, `.mypy_cache`, `.pytest_cache`, `Pods`, `DerivedData`, etc.
- User prunes: additionally skip directories/paths with `--ignore <name-or-glob>` (repeat as needed).
- Skipped files: locks (`yarn.lock`, `pnpm-lock.yaml`, etc.), secrets (`.env*`, `*.pem`), binaries, large assets/images, archives, minified bundles (`*.min.js`), source maps.
- Non-UTF-8 files are skipped with a warning to avoid emitting empty content.

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
- Ignore support (same style as Megaprompter):
  - `--ignore nameOrGlob` (repeatable; aliases: `-I`, `-i`)
  - Filters diagnostics and Python file enumeration
- Outputs:
  - XML diagnostics (to stdout by default; configurable via `--xml-out`)
  - JSON diagnostics (`--json-out`)
  - Fix prompt (`--prompt-out`)
  - Artifact in the target directory: `MEGADIAG_YYYYMMDD_HHMMSS` (visible by default)
    - Optional hidden dotfile: `.MEGADIAG_YYYYMMDD_HHMMSS` with `--artifact-hidden`
    - Convenience symlink updated on each run: `MEGADIAG_latest` or `.MEGADIAG_latest` (if hidden)

### Usage

```bash
# Diagnose a project tree (writes a visible artifact in the directory)
megadiagnose .

# Write the artifact as a hidden dotfile (.MEGADIAG_*)
megadiagnose . --artifact-hidden

# Choose a directory for the artifact (defaults to the target path)
megadiagnose . --artifact-dir artifacts/

# Ignore directories/files by name or glob (repeatable)
megadiagnose . --ignore data --ignore docs/generated/** --ignore .cache/**

# Save outputs to files in addition to the artifact
megadiagnose . --xml-out diag.xml --json-out diag.json --prompt-out fix_prompt.txt

# Increase timeout per tool (seconds)
megadiagnose . --timeout-seconds 180

# Force run even if heuristics do not detect a code project
megadiagnose . --force
```

#### Command Options

```
USAGE: megadiagnose [<path>] [--force] [--timeout-seconds <int>] [--xml-out <path>] [--json-out <path>] [--prompt-out <path>] [--show-summary|--no-show-summary] [--artifact-hidden] [--artifact-dir <path>] [--ignore <name-or-glob> ...]

ARGUMENTS:
  <path>                 Target directory ('.' by default). Accepts relative or absolute paths.

OPTIONS:
  --force                Force run even if the directory does not look like a code project.
  --timeout-seconds      Timeout in seconds per tool invocation (default: 120).
  --xml-out              Write XML output to this file (default: stdout).
  --json-out             Write JSON output to this file.
  --prompt-out           Write fix prompt text to this file.
  --show-summary         Print a brief summary to stderr (default: on).
  --no-show-summary      Disable the summary.
  --artifact-hidden      Write artifact as a hidden dotfile (.MEGADIAG_*). Default is visible (MEGADIAG_*).
  --artifact-dir         Directory where the MEGADIAG_* artifact is written (default: the target path).
  --ignore               Directory names or glob paths to ignore (repeatable).
                         Examples: --ignore data --ignore docs/generated/**
                         Short aliases: -I, -i
  -h, --help             Show help information.
```

### What it Writes

- A single artifact file in your target directory (or `--artifact-dir`):
  - Visible: `MEGADIAG_YYYYMMDD_HHMMSS`
  - Hidden: `.MEGADIAG_YYYYMMDD_HHMMSS` (if `--artifact-hidden` is used)
- The artifact is a pseudo‑XML envelope that embeds:
  - `<xml>`: the XML diagnostics summary (uses neutral `<issue>` elements; includes per-language issue summaries and a fix_prompt section).
  - `<json>`: the same diagnostics in JSON.
  - `<fix_prompt>`: a short, actionable prompt for LLMs to produce minimal patches.
- A convenience symlink to the most recent artifact:
  - `MEGADIAG_latest` (visible) or `.MEGADIAG_latest` (hidden)

Example (truncated):

```xml
<diagnostics_artifact generatedAt="2024-10-25T12:34:56Z">
  <xml>
    <![CDATA[
<diagnostics>
  <language name="swift" tool="swift build">
    <issue file="Sources/App/main.swift" line="12" column="5" severity="error" code="">
      <![CDATA[cannot find 'Foo' in scope]]>
    </issue>
    <summary count="1" errors="1" warnings="0" />
  </language>
  <summary total_languages="1" total_issues="1" />
  <fix_prompt>
    <![CDATA[...]]>
  </fix_prompt>
</diagnostics>
    ]]>
  </xml>
  <json>
    <![CDATA[{ ... }]]>
  </json>
  <fix_prompt>
    <![CDATA[...instructions and top issues...]]>
  </fix_prompt>
</diagnostics_artifact>
```

---

## Safety Features (both tools)

- Refuse to run if the target directory doesn’t look like a code project (use `--force` to override).
- Skip oversized files by default (Megaprompter `--max-file-bytes`) to avoid grabbing huge artifacts.
- Skip `.env*` and common secret/binary extensions by design in Megaprompter’s selection rules.
- Megadiagnose only runs tools it can find on your PATH and times out each tool invocation.

---

## Troubleshooting

- Permission denied while linking  
  Use sudo when linking into system paths:

  ```bash
  sudo ln -sf "$PWD/.build/release/megaprompt" /usr/local/bin/megaprompt
  sudo ln -sf "$PWD/.build/release/megadiagnose" /usr/local/bin/megadiagnose
  ```

  Alternatively, link into a user‑writable PATH directory (e.g., `~/bin`) and ensure it’s on your PATH.

- “No such module 'ArgumentParser'” in Xcode  
  This can appear during indexing if the package graph wasn’t resolved. From the project root:

  ```bash
  swift package reset
  swift package resolve
  swift build -c release
  ```

  Then reopen the package in Xcode if desired.

- Clipboard didn’t copy (megaprompt)  
  The tool tries `pbcopy` → `wl-copy` → `xclip` → `xsel` → (Windows) `clip`. If none are present, it still writes the `.MEGAPROMPT_*` file. Install one of those tools or copy from the file manually. On X11 systems, selection owners can be transient — consider pasting immediately after copying.

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
```

---

## Uninstall

```bash
sudo rm -f /usr/local/bin/megaprompt
sudo rm -f /usr/local/bin/megadiagnose
# (or wherever you linked them)
```

---

## License

MIT (see `LICENSE` if present).
