# executable-stories-action

Surface [executable-stories](https://github.com/jagreehal/executable-stories) test output in pull requests. Posts a Markdown summary as a PR comment and uploads the full HTML report as a downloadable artifact.

Works with all supported frameworks — zero configuration for the common case.

## Quick Start

Add to your workflow after the test step:

```yaml
- uses: jagreehal/executable-stories-action@v1
```

That's it. The action auto-detects your test output.

## How It Works

The action checks for test output in two places:

1. **Pre-generated reports** — If `reports/test-results.html` and `reports/test-results.md` exist (the default output from JS/TS framework reporters), the action uses them directly.

2. **Raw run JSON** — If `.executable-stories/raw-run.json` exists (the default output from non-JS adapters like pytest, Go, Rust, JUnit5, xUnit), the action downloads the `executable-stories` CLI binary and generates the reports.

## Examples

### Vitest / Jest / Playwright

Your framework reporter already generates HTML + Markdown:

```yaml
name: CI
on: [pull_request]
permissions:
  pull-requests: write

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - run: pnpm install
      - run: pnpm test

      - uses: jagreehal/executable-stories-action@v1
```

### Python (pytest)

```yaml
name: CI
on: [pull_request]
permissions:
  pull-requests: write

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: pip install -e ".[test]"
      - run: pytest

      - uses: jagreehal/executable-stories-action@v1
```

### Go

```yaml
name: CI
on: [pull_request]
permissions:
  pull-requests: write

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: "1.22"
      - run: go test ./...

      - uses: jagreehal/executable-stories-action@v1
```

### Custom Output Paths

If you configured your reporter with custom `outputDir` or `outputName`:

```yaml
      - uses: jagreehal/executable-stories-action@v1
        with:
          report-dir: docs/stories
          output-name: user-stories
```

### Pinned Formatter Version

```yaml
      - uses: jagreehal/executable-stories-action@v1
        with:
          formatter-version: "0.7.3"
```

### Render Screenshots Inline in PR Comments (opt-in)

By default, screenshots referenced in your tests are kept in the HTML artifact only — the PR comment shows a `📎 Screenshot (see HTML report)` placeholder. This is because GitHub blocks `data:` URIs in comment markdown.

To make screenshots render inline in the PR comment, opt in:

```yaml
permissions:
  pull-requests: write
  contents: write          # required: action commits images on a dedicated branch

jobs:
  test:
    steps:
      # ...run tests...
      - uses: jagreehal/executable-stories-action@v1
        with:
          host-images: branch
          # images-branch: executable-stories-images   # optional, this is the default
```

What this does:
- Per PR run, screenshots are committed to an orphan branch (`executable-stories-images` by default), under `pr-{number}/{run-id}/`
- The PR comment is rewritten to use `https://raw.githubusercontent.com/...` URLs so images render inline
- The branch is created automatically on first use; safe to delete old `pr-*/` directories any time
- If the branch upload fails (e.g. permission denied), the action falls back to placeholder mode without breaking the comment

## Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `report-dir` | `reports` | Directory containing or receiving generated reports |
| `output-name` | `test-results` | Base filename for reports (without extension) |
| `raw-run` | `.executable-stories/raw-run.json` | Path to raw run JSON |
| `formatter-version` | `latest` | Version of executable-stories binary (`latest` or semver) |
| `artifact-name` | `executable-stories-report` | Name for the uploaded GitHub artifact |
| `comment-title` | `Executable Stories` | Header text for the PR comment |
| `host-images` | `false` | Set to `branch` to commit screenshots to an orphan branch and render them inline in the PR comment. Requires `contents: write`. |
| `images-branch` | `executable-stories-images` | Branch used when `host-images: branch`. Created as orphan on first use. |

## Outputs

| Output | Description |
|--------|-------------|
| `html-report-path` | Path to the HTML report file |
| `markdown-report-path` | Path to the Markdown report file |
| `comment-id` | ID of the created or updated PR comment |

## Permissions

The workflow needs `pull-requests: write` to post comments:

```yaml
permissions:
  pull-requests: write
```

If you opt in to `host-images: branch`, also grant `contents: write` so the action can commit screenshots to the images branch:

```yaml
permissions:
  pull-requests: write
  contents: write
```

## What You See in PRs

The action creates a comment on your PR with:

- A collapsible section containing the full Markdown story output
- A link to download the interactive HTML report from the workflow artifacts

On subsequent pushes, the comment is updated (not duplicated).

## Supported Frameworks

| Framework | Output Type | Config Needed |
|-----------|------------|---------------|
| Vitest | HTML + Markdown (via StoryReporter) | None |
| Jest | HTML + Markdown (via reporter) | None |
| Playwright | HTML + Markdown (via reporter) | None |
| Cypress | HTML + Markdown (via reporter) | None |
| pytest | Raw JSON | None |
| Go | Raw JSON | None |
| Rust | Raw JSON | None |
| JUnit5 (Kotlin) | Raw JSON | None |
| xUnit (C#) | Raw JSON | None |
