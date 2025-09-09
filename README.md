# Megaprompter

Generate a single **XML-like megaprompt** containing the *real* source files and essential configs from your project (tests included) — perfect for pasting into LLMs or code review tools.

* **Safety first:** refuses to run outside a code project (override with `--force`).
* **Smart detection:** identifies TypeScript/JS, Swift, Python, Go, Rust, Java/Kotlin, C/C++, C#, PHP, Ruby, Terraform, etc.
* **Language-aware rules:** prefers `.ts/.tsx` over `.js/.jsx` when TS is present; includes CI (GitHub Actions) YAML.
* **Pruning:** skips vendor, build, and cache directories for speed and relevance.
* **Output:** one blob with each file wrapped as a tag of its relative path and the content in `CDATA`.
* **Persistence + Clipboard:** writes `.MEGAPROMPT_YYYYMMDD_HHMMSS` and copies the same text to your clipboard.

---

## Requirements

* **Swift**: 6.x (tested with 6.0+)
* **Platform**: macOS 13+ (Linux & Windows build, but clipboard support varies)
* **Clipboard utilities**: one of `pbcopy` (macOS), `wl-copy` (Wayland), `xclip`/`xsel` (X11), or `clip` (Windows). If none is found, the file is still written.

---

## Build & Install

```bash
# Clone this repository, then:
swift package resolve
swift build -c release
```

Add the executable to your PATH (macOS example):

```bash
# If /usr/local/bin requires elevated permissions:
sudo ln -sf "$PWD/.build/release/megaprompt" /usr/local/bin/megaprompt
```

> If you saw `ln: /usr/local/bin/megaprompt: Permission denied`, re-run with `sudo` as above.

To update later, rebuild and re-link.

---

## Usage

From a project root:

```bash
megaprompt .
```

Target only a subdirectory:

```bash
megaprompt packages/app
megaprompt foo/bar
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

### Command Options

```
USAGE: megaprompt [<path>] [--force] [--max-file-bytes <int>] [--dry-run] [--show-summary]

ARGUMENTS:
  <path>                 Target directory ('.' by default). Accepts relative or absolute paths.

OPTIONS:
  --force                Force run even if the directory does not look like a code project.
  --max-file-bytes       Skip files larger than this many bytes (default: 1500000).
  --dry-run              Only show what would be included; do not write or copy.
  --show-summary         Print a summary of detected project types and included files.
  -h, --help             Show help information.
```

---

## What it Outputs

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

> Tag names are the **relative file paths**. It’s intentionally pseudo-XML to keep things copy-paste friendly for LLMs.

---

## How It Decides What To Include

* **Language detection:** Looks for canonical markers (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `Package.swift`, etc.) and/or ≥8 recognizable source files.
* **TypeScript preference:** If TypeScript is present, `.js`/`.jsx` are *excluded*; `.mjs`/`.cjs` (Node configs) remain allowed.
* **Always include** certain config files by exact name (e.g., `package.json`, `pyproject.toml`, `Dockerfile`, `Makefile`, `tsconfig.json`, `eslint`/`prettier` configs).
* **Always include** GitHub Actions/Actions YAML:

  * `.github/workflows/*.yml|yaml`
  * `.github/actions/**/*.yml|yaml`
* **Treat tests as code:** files/folders matching common patterns (`*.test.*`, `*.spec.*`, `__tests__`, `tests`, `spec`, etc.).
* **Pruned directories** (partial list):
  `node_modules`, `.git`, `.next`, `dist`, `build`, `out`, `target`, `bin`, `obj`, `vendor`, `.terraform`, `.gradle`, `.idea`, `.vscode`, `__pycache__`, `.mypy_cache`, `.pytest_cache`, `Pods`, `DerivedData`, etc.
* **Skipped files:** locks (`yarn.lock`, `pnpm-lock.yaml`, etc.), secrets (`.env*`, `*.pem`), binaries, large assets/images, archives, minified bundles (`*.min.js`), source maps.

---

## Safety Features

* Refuses to run if the target directory doesn’t look like a code project (use `--force` to override).
* Skips oversized files by default (`--max-file-bytes`), protecting against accidental ingestion of large artifacts.
* Skips `.env*` and common secret/binary extensions.

---

## Troubleshooting

* **`Permission denied` while linking**
  Use `sudo` when linking into system paths:

  ```bash
  sudo ln -sf "$PWD/.build/release/megaprompt" /usr/local/bin/megaprompt
  ```

  Alternatively, link into a user-writable PATH directory (e.g., `~/bin`) and ensure it’s on your PATH.

* **`No such module 'ArgumentParser'` in Xcode**
  This can appear during indexing if the package graph wasn’t resolved. From the project root:

  ```bash
  swift package reset
  swift package resolve
  swift build -c release
  ```

  Then reopen the package in Xcode if desired.

* **Clipboard didn’t copy**
  The tool tries `pbcopy` → `wl-copy` → `xclip` → `xsel` → `clip`. If none are present, it still writes the `.MEGAPROMPT_*` file. Install one of those tools or copy from the file manually.

* **Too many files included / excluded**
  Use `--dry-run --show-summary` to see the exact file list. If you need different behavior, adjust the rules in `Sources/MegaprompterCore/Rules.swift` (allowed extensions, forced includes, prunes).

---

## Example Workflows

* Generate a megaprompt for a sub-package and paste into ChatGPT:

  ```bash
  megaprompt packages/app
  pbpaste | wc -l         # sanity check lines
  ```

* Create a fresh blob but preview file list first:

  ```bash
  megaprompt . --dry-run --show-summary
  megaprompt .
  ```

* Tighten size limits (e.g., for monorepos):

  ```bash
  megaprompt . --max-file-bytes 300000
  ```

---

## Security Notes

* Megaprompter **does not** read `.env*` by design, but **you** are responsible for what you paste elsewhere. Review the generated `.MEGAPROMPT_*` file before sharing.
* Consider committing the `.MEGAPROMPT_*` files to `.gitignore`.

---

## Development

Build:

```bash
swift build
swift test
```

Run without installing:

```bash
swift run megaprompt .
```

---

## Uninstall

```bash
sudo rm -f /usr/local/bin/megaprompt
# (or wherever you linked it)
```

---

## License

MIT (see `LICENSE` if present).
