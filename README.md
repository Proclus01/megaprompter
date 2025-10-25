# Megaprompter

Generate a single XML-like megaprompt containing the real source files and essential configs from your project (tests included) — perfect for pasting into LLMs or code review tools.

- Safety first: refuses to run outside a code project (override with `--force`).
- Smart detection: identifies TypeScript/JS, Swift, Python, Go, Rust, Java/Kotlin, C/C++, C#, PHP, Ruby, Terraform, etc.
- Language-aware rules: prefers `.ts/.tsx` over `.js/.jsx` when TS is present; includes CI (GitHub Actions) YAML.
- Pruning: skips vendor, build, and cache directories for speed and relevance. You can also pass your own prunes with `--ignore`.
- Output: one blob with each file wrapped as a tag of its relative path and the content in `CDATA`.
- Persistence + Clipboard: writes `.MEGAPROMPT_YYYYMMDD_HHMMSS` and copies the same text to your clipboard.

---

## MegaDiagnose (Project Diagnostics)

A companion CLI that scans your project, runs language-appropriate compilers/checkers, captures errors/warnings, and emits a compact XML diagnostic summary plus a ready-to-use "fix prompt" for LLMs.

- Executable: `megadiagnose`
- Automatic detection of project languages (reuses Megaprompter detector).
- Executes relevant tools when available:
  - Swift (SwiftPM): `swift build`
  - TypeScript: `npx -y tsc -p . --noEmit`
  - JavaScript fallback: `npm run -s build` if present
  - Go: deep scan across ALL packages (go list ./...; go build -gcflags=all=-e <pkg>)
  - Rust: `cargo check --color never`
  - Python: `python3 -m py_compile` on each `.py` file
  - Java: `mvn -q -DskipTests compile` or `gradle -q classes`
- Ignore support (same style as Megaprompter):
  - `--ignore nameOrGlob` (repeatable; aliases: `-I`, `-i`)
  - Filters diagnostics and Python file enumeration

New in this patch:
- Always writes a MEGADIAG_* artifact up front (even when XML goes to stdout).
- Creates/updates a convenience symlink:
  - `MEGADIAG_latest` (visible) or `.MEGADIAG_latest` (hidden), next to the artifact.
- You can choose the artifact directory with `--artifact-dir DIR`.

### Install

```bash
swift package resolve
swift build -c release
sudo ln -sf "$PWD/.build/release/megaprompt" /usr/local/bin/megaprompt
sudo ln -sf "$PWD/.build/release/megadiagnose" /usr/local/bin/megadiagnose
```

### Usage

```bash
# Diagnose a project tree (writes a visible artifact in the directory)
megadiagnose .

# Write the artifact as a hidden dotfile (.MEGADIAG_*)
megadiagnose . --artifact-hidden

# Choose a custom directory for the artifact
megadiagnose . --artifact-dir ./diagnostics

# Ignore directories/files by name or glob (repeatable)
megadiagnose . --ignore data --ignore docs/generated/** --ignore .cache/**

# Save outputs to files in addition to the artifact
megadiagnose . --xml-out diag.xml --json-out diag.json --prompt-out fix_prompt.txt

# Increase timeout per tool (seconds)
megadiagnose . --timeout-seconds 180

# Force run even if heuristics do not detect a code project
megadiagnose . --force
```

Outputs:
- XML diagnostics (to stdout by default; configurable via `--xml-out`)
- JSON diagnostics (`--json-out`)
- Fix prompt (`--prompt-out`)
- Artifact file in the target directory: `MEGADIAG_YYYYMMDD_HHMMSS` (visible by default)
  - Optional: hidden variant `.MEGADIAG_YYYYMMDD_HHMMSS` with `--artifact-hidden`
  - Convenience symlink: `MEGADIAG_latest` (or `.MEGADIAG_latest`) updated on each run

---

## Build & Test

```bash
swift build -c release
swift test
```

