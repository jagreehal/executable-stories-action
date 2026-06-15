# executable-stories-action

Surface [executable-stories](https://github.com/jagreehal/executable-stories) test output in pull requests. Posts a Markdown summary as a PR comment and uploads the full HTML report as a downloadable artifact.

Works with all supported frameworks — zero configuration for the common case.

> **Looking for the user-friendly docs?** See [executablestories.com/guides/github-action](https://executablestories.com/guides/github-action/).

## Contents

- [Quick start](#quick-start)
- [Prerequisites](#prerequisites)
- [How it works](#how-it-works)
- [Examples by framework](#examples-by-framework)
- [Recipes](#recipes)
  - [Always post the comment, even on test failure](#always-post-the-comment-even-on-test-failure)
  - [Multiple reports per PR](#multiple-reports-per-pr)
  - [Render screenshots inline (opt-in)](#render-screenshots-inline-in-pr-comments-opt-in)
  - [Custom output paths](#custom-output-paths)
  - [Pinned formatter version](#pinned-formatter-version)
  - [Using the action's outputs](#using-the-actions-outputs)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [Permissions](#permissions)
- [What you see in PRs](#what-you-see-in-prs)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Supported frameworks](#supported-frameworks)

## Quick start

```yaml
- uses: jagreehal/executable-stories-action@v1
```

The action auto-detects your test output. No inputs are required for the default flow.

## Prerequisites

The action does **not** run your tests — it surfaces the output of an `executable-stories` reporter that has already run. You need one of these set up first:

| Framework | Setup guide |
|---|---|
| Vitest | [Installation (Vitest)](https://executablestories.com/getting-started/installation-vitest/) |
| Jest | [Installation (Jest)](https://executablestories.com/getting-started/installation-jest/) |
| Playwright | [Installation (Playwright)](https://executablestories.com/getting-started/installation-playwright/) |
| Cypress | [Installation (Cypress)](https://executablestories.com/getting-started/installation-cypress/) |
| pytest | [Installation (pytest)](https://executablestories.com/getting-started/installation-pytest/) |
| Go | [Installation (Go)](https://executablestories.com/getting-started/installation-go/) |
| Rust | [Installation (Rust)](https://executablestories.com/getting-started/installation-rust/) |
| Ruby (Minitest) | [Installation (Ruby)](https://executablestories.com/getting-started/installation-ruby/) |
| JUnit 5 (Kotlin) | [Installation (JUnit 5)](https://executablestories.com/getting-started/installation-junit5/) |
| xUnit (C#) | [Installation (xUnit)](https://executablestories.com/getting-started/installation-xunit/) |

If your test command does not produce **either** `reports/test-results.{html,md}` **or** `.executable-stories/raw-run.json`, the action has nothing to surface and will fail with a "no reports found" error. See [Troubleshooting](#troubleshooting).

## How it works

The action checks for test output in two places, in order:

1. **Pre-generated reports** — if `reports/test-results.html` and `reports/test-results.md` exist (the default output from JS/TS framework reporters), the action uses them directly.
2. **Raw run JSON** — if `.executable-stories/raw-run.json` exists (the default output from non-JS adapters like pytest, Go, Rust, JUnit 5, xUnit), the action downloads the `executable-stories` CLI binary and generates the reports.

In both cases the action then:

- Uploads `test-results.html` as a workflow artifact
- Posts (or updates) a PR comment containing the markdown summary
- Sets outputs you can chain to subsequent steps

## Examples by framework

All examples assume you already have an executable-stories reporter configured (see [Prerequisites](#prerequisites)).

### Vitest / Jest / Playwright

The reporter generates HTML and Markdown directly:

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
        if: always()  # post the comment even when tests fail
```

### Cypress

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
      - run: pnpm cypress run

      - uses: jagreehal/executable-stories-action@v1
        if: always()
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
        if: always()
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
        if: always()
```

### Rust

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
      - uses: dtolnay/rust-toolchain@stable
      - run: cargo test

      - uses: jagreehal/executable-stories-action@v1
        if: always()
```

### Ruby (Minitest)

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
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true
      - run: bundle exec rake test

      - uses: jagreehal/executable-stories-action@v1
        if: always()
```

### JUnit 5 (Kotlin)

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
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "21"
      - run: ./gradlew test

      - uses: jagreehal/executable-stories-action@v1
        if: always()
```

### xUnit (C#)

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
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: "8.0"
      - run: dotnet test

      - uses: jagreehal/executable-stories-action@v1
        if: always()
```

## Recipes

### Always post the comment, even on test failure

Without `if: always()`, the action only runs if the previous step succeeded. For test feedback, you almost always want the comment to post even when tests fail:

```yaml
      - run: pnpm test

      - uses: jagreehal/executable-stories-action@v1
        if: always()
```

### Multiple reports per PR

You can run the action more than once per workflow — for example, separate Vitest and Playwright suites that should each get their own PR comment. Use a unique `comment-title` for each invocation; the action looks for an existing comment matching `<!-- executable-stories: ${comment-title} -->`, so distinct titles produce distinct comments that update independently:

```yaml
      - run: pnpm test:unit
      - if: always() && hashFiles('docs/evidence/vitest-tests.html') != ''
        uses: jagreehal/executable-stories-action@v1
        with:
          report-dir: docs/evidence
          output-name: vitest-tests
          artifact-name: executable-stories-vitest
          comment-title: Vitest Stories

      - run: pnpm test:e2e
      - if: always() && hashFiles('docs/evidence/playwright-tests.html') != ''
        uses: jagreehal/executable-stories-action@v1
        with:
          report-dir: docs/evidence
          output-name: playwright-tests
          artifact-name: executable-stories-playwright
          comment-title: Playwright Stories
```

The `hashFiles(...)` guards skip the action when a test suite produced no output (e.g. earlier suite errored before writing).

### Render screenshots inline in PR comments (opt-in)

By default, screenshots referenced in your stories stay in the HTML artifact only — the PR comment shows a `📎 alt (see HTML report)` placeholder. This is because GitHub blocks `data:` URIs in comment markdown for security, so even a well-formed `![alt](data:image/png;base64,…)` would not render inline.

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

- Per PR run, the action commits each screenshot to an orphan branch (`executable-stories-images` by default) under `pr-{number}/{run-id}/`
- The PR comment is rewritten to use `https://raw.githubusercontent.com/...` URLs so images render inline
- The branch is created automatically on first use, with a small README explaining what it is. Old `pr-*/` directories are safe to delete at any time
- If the upload fails (e.g. `contents: write` not granted, or a concurrent run races on the ref), the action falls back to placeholder mode and posts a warning. The comment still renders cleanly.

> **Concurrency note.** The action commits using the GitHub Git Data API by referencing the branch's current tip as the parent. If two PR runs touch the same `images-branch` simultaneously, the second `updateRef` call will fail with a non-fast-forward error and the action will fall back to placeholders for that run. There's no retry yet — see [executable-stories-action#1](https://github.com/jagreehal/executable-stories-action/pull/1) for context. For most repos this is rare; if you regularly run many parallel PRs and need bullet-proof inline images, consider giving each workflow a different `images-branch`.

### Custom output paths

If your reporter is configured with custom `outputDir` or `outputName`:

```yaml
      - uses: jagreehal/executable-stories-action@v1
        with:
          report-dir: docs/stories
          output-name: user-stories
```

### Pinned formatter version

Pin the `executable-stories` CLI version that the action downloads (only relevant for the raw-JSON path used by non-JS adapters):

```yaml
      - uses: jagreehal/executable-stories-action@v1
        with:
          formatter-version: "0.7.3"
```

### Using the action's outputs

```yaml
      - id: stories
        uses: jagreehal/executable-stories-action@v1

      - name: Echo report paths
        run: |
          echo "html: ${{ steps.stories.outputs.html-report-path }}"
          echo "md:   ${{ steps.stories.outputs.markdown-report-path }}"
          echo "comment id: ${{ steps.stories.outputs.comment-id }}"

      - name: Reply to the comment with a chained note
        if: github.event_name == 'pull_request' && steps.stories.outputs.comment-id != ''
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `Stories comment id: ${{ steps.stories.outputs.comment-id }}`,
            });
```

### Gate a release against a dev baseline (`mode: gate-release`)

Fail the build if a release candidate regresses, drops, or (optionally) adds scenarios versus a known-good dev run. The comparison report is uploaded as an artifact and the `gate-failed` output is set.

```yaml
- uses: jagreehal/executable-stories-action@v1
  with:
    mode: gate-release
    raw-run: .executable-stories/rc-run.json        # the release candidate
    gate-dev-run: .executable-stories/dev-run.json  # the baseline
    # gate-fail-on-new: true                          # also fail on unexpected new scenarios
    # gate-release-policy: .es/release-policy.json    # allow specific exceptions
```

By default regressions and removals fail the gate; new scenarios do not (`gate-fail-on-new: false`).

### Record a deployment (`mode: deploy`)

Append a deployment to an environment ledger so later runs (and `gate-release`) can reason about what's where.

```yaml
- uses: jagreehal/executable-stories-action@v1
  with:
    mode: deploy
    deploy-env: production
    deploy-tag: ${{ github.ref_name }}
    # deploy-ledger: .executable-stories/deployments.json   # default
```

Persist the ledger (artifact, cache, or committed file) if later jobs should compare environments. The written path is exposed as `deploy-ledger-path`.

### Living-Docs Portal — self-hostable static site (`mode: portal`)

Turn a test run into a deployable static site that is your team's source of truth: scenarios categorized by audience (engineers = unit/integration, stakeholders = e2e with video/otel), a "What's changed" view, and stable per-scenario deep-links you can paste into Linear or Confluence. Host it anywhere — the action produces a host-agnostic artifact, and can optionally publish to GitHub Pages.

Artifact only (deploy to S3, internal nginx, Netlify, …):

```yaml
jobs:
  portal:
    runs-on: ubuntu-latest
    steps:
      # ...run tests, then ensure the Astro site deps are installed...
      - run: npm ci
      - uses: jagreehal/executable-stories-action@v1
        with:
          mode: portal
          portal-site-dir: docs-site        # scaffold once: executable-stories init-astro
          # portal-baseline: prev-story-report.json   # optional → adds the What's-changed page
      # download the `executable-stories-portal` artifact and deploy it wherever you like
```

Ownership model:
- Commit the **portal source**: `portal-site-dir`, including `src/content/docs/guides/`, `notes/`, `adr/`, `runbooks/`, and your Astro config/theme customizations.
- Do **not** treat generated `src/content/docs/stories/` or `public/stories/*` as hand-edited source. `build-docs` regenerates them on every run.
- The `init-astro` scaffold now ships a `.gitignore` for those generated paths, so git defaults toward tracking the human zone, not the latest test output.

Publish to GitHub Pages:

```yaml
permissions:
  contents: read
  pages: write
  id-token: write

jobs:
  portal:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.portal.outputs.portal-url }}
    steps:
      - run: npm ci
      - id: portal
        uses: jagreehal/executable-stories-action@v1
        with:
          mode: portal
          portal-site-dir: docs-site
          portal-publish: pages
```

Notes:
- `portal-build` (default `true`) runs `npm run build` in `portal-site-dir`; set it `false` to upload prepared content and build elsewhere.
- For the **What's changed** page, persist the previous run's `public/stories/story-report.json` (artifact/cache) and pass it as `portal-baseline`.
- The action exposes the current report as `portal-story-report-path`, so you can save it separately as a lightweight baseline artifact without scraping paths yourself.

Persist the baseline report artifact:

```yaml
jobs:
  portal:
    runs-on: ubuntu-latest
    steps:
      - run: npm ci
      - id: portal
        uses: jagreehal/executable-stories-action@v1
        with:
          mode: portal
          portal-site-dir: docs-site
      - uses: actions/upload-artifact@v4
        with:
          name: executable-stories-portal-baseline
          path: ${{ steps.portal.outputs.portal-story-report-path }}
```

Cache-backed baseline round-trip on the same branch:

```yaml
jobs:
  portal:
    runs-on: ubuntu-latest
    steps:
      - run: npm ci
      - uses: actions/cache/restore@v4
        id: portal-baseline-restore
        with:
          path: .cache/executable-stories/portal-baseline.json
          key: portal-baseline-${{ github.ref_name }}-${{ github.run_id }}
          restore-keys: |
            portal-baseline-${{ github.ref_name }}-
      - id: portal
        uses: jagreehal/executable-stories-action@v1
        with:
          mode: portal
          portal-site-dir: docs-site
          portal-baseline: ${{ steps.portal-baseline-restore.outputs.cache-hit && '.cache/executable-stories/portal-baseline.json' || '' }}
      - run: |
          mkdir -p .cache/executable-stories
          cp "${{ steps.portal.outputs.portal-story-report-path }}" .cache/executable-stories/portal-baseline.json
      - uses: actions/cache/save@v4
        if: always()
        with:
          path: .cache/executable-stories/portal-baseline.json
          key: portal-baseline-${{ github.ref_name }}-${{ github.run_id }}
```

## Inputs

| Input | Default | Description |
|---|---|---|
| `mode` | `report` | `report`, `review`, `gate-release`, `deploy`, or `portal` |
| `report-dir` | `reports` | Directory containing or receiving generated reports |
| `output-name` | `test-results` | Base filename for reports (without extension) |
| `raw-run` | `.executable-stories/raw-run.json` | Path to raw run JSON |
| `formatter-version` | `latest` | Version of `executable-stories` binary (`latest` or semver, e.g. `0.7.12`) |
| `artifact-name` | `executable-stories-report` | Name for the uploaded GitHub artifact |
| `comment-title` | `Executable Stories` | Header text for the PR comment; also used as the marker that lets the action find and update its own comment on subsequent runs |
| `host-images` | `false` | Set to `branch` to commit screenshots to an orphan branch and render them inline in the PR comment. Requires `contents: write`. See [Render screenshots inline](#render-screenshots-inline-in-pr-comments-opt-in). |
| `images-branch` | `executable-stories-images` | Branch used when `host-images: branch`. Created as orphan on first use. |
| `run-json` | — | (review) Path to the run JSON to correlate against the PR diff. Defaults to `raw-run` |
| `base-ref` | — | (review) Base ref to diff against. Defaults to the PR base branch |
| `changed-files` | — | (review) Optional precomputed changed-files file. If unset, computed from git |
| `fail-on` | — | (review) Opt-in gate: `uncovered` or `weak` — fail when changed code lacks evidence |
| `min-evidence` | — | (review) Opt-in gate: `weak`, `moderate`, or `strong` — fail when claims are below this strength |
| `formatter-binary` | — | Path to a prebuilt `executable-stories` binary instead of downloading from Releases |
| `gate-dev-run` | — | (gate-release) Path to the dev test run used as the baseline |
| `gate-fail-on-regression` | `true` | (gate-release) Fail if scenarios regressed from dev to the RC |
| `gate-fail-on-removal` | `true` | (gate-release) Fail if scenarios present in dev are missing from the RC |
| `gate-fail-on-new` | `false` | (gate-release) Fail if the RC adds scenarios not in dev |
| `gate-release-policy` | — | (gate-release) Path to a release-policy JSON with allowed exceptions |
| `deploy-env` | — | (deploy) Environment name to record the deployment against (e.g. `staging`) |
| `deploy-tag` | — | (deploy) Git tag for this deployment (e.g. `v1.2.3`) |
| `deploy-ledger` | `.executable-stories/deployments.json` | (deploy) Path to the deployment ledger JSON |
| `portal-site-dir` | `.` | (portal) Root of the Astro site to generate the portal into |
| `portal-baseline` | — | (portal) Path to a previous `story-report.json`; enables the What's-changed page |
| `portal-audience-split` | `true` | (portal) Group pages into `/stories/engineer\|stakeholder/`. Set `false` for flat `/stories/<file>/` URLs |
| `portal-build` | `true` | (portal) Run the site build after generating content |
| `portal-build-command` | `npm run build` | (portal) Command run inside `portal-site-dir` to build the site |
| `portal-dist-dir` | `dist` | (portal) Build output dir, relative to `portal-site-dir` |
| `portal-publish` | `false` | (portal) `pages` to also deploy to GitHub Pages |
| `portal-artifact-name` | `executable-stories-portal` | (portal) Name for the uploaded portal artifact |

## Outputs

| Output | Description |
|---|---|
| `html-report-path` | Path to the generated HTML report file |
| `markdown-report-path` | Path to the generated Markdown report file |
| `comment-id` | Numeric ID of the PR comment that was created or updated. Empty string when the action runs outside a `pull_request` event. |
| `gate-failed` | (gate-release, review) `true`/`false` — whether the gate failed |
| `deploy-ledger-path` | (deploy) Path to the deployment ledger written in deploy mode |
| `portal-output-path` | (portal) Path to the built portal site |
| `portal-story-report-path` | (portal) Path to the generated `public/stories/story-report.json` for baseline persistence |
| `portal-url` | (portal) Published GitHub Pages URL when `portal-publish: pages` |

## Permissions

The minimum required permissions:

```yaml
permissions:
  pull-requests: write   # post and update PR comments
```

If you opt in to `host-images: branch`, also grant `contents: write` so the action can commit screenshots to the images branch:

```yaml
permissions:
  pull-requests: write
  contents: write
```

For PRs from forks, GitHub restricts the default `GITHUB_TOKEN` to read-only — see [FAQ](#faq) for workarounds.

## What you see in PRs

Each invocation produces:

- A collapsible section in a PR comment containing the full Markdown story output
- A link at the bottom of that comment to download the interactive HTML report from the workflow's artifacts
- (Optional, with `host-images: branch`) Screenshots rendered inline in the comment

On subsequent pushes to the same PR, the comment is **updated in place** rather than duplicated. Comments are matched by an HTML marker (`<!-- executable-stories: ${comment-title} -->`), so the same `comment-title` always updates the same comment, while different titles produce different comments (see [Multiple reports per PR](#multiple-reports-per-pr)).

## Troubleshooting

### "No reports found"

The action's first step says it could not find pre-generated reports or a raw run JSON. Causes:

- Your test command finished but did not write anything to `reports/test-results.{html,md}` or `.executable-stories/raw-run.json`. Check the reporter is wired up — see [Prerequisites](#prerequisites) for the per-framework setup guide.
- You configured a custom output path. Match it with `report-dir` / `output-name` (or `raw-run` for the JSON path).
- The previous step (your test runner) errored before writing output, and you did not use `if: always()` on the action step.

### The PR comment never appears

- Confirm the workflow has `permissions: pull-requests: write`.
- Confirm the action ran on a `pull_request` event (not a `push` to a branch — the action only comments on PRs).
- For PRs from forks, the default `GITHUB_TOKEN` is read-only by design; the action will silently skip the comment step. See [FAQ](#faq).

### Screenshots show as 📎 placeholders, not images

This is the default. GitHub blocks `data:` URIs in comment markdown, so inline base64 images would not render even if we left them in. Opt in to [host-images: branch](#render-screenshots-inline-in-pr-comments-opt-in) to render them inline.

### `host-images: branch` warned and fell back to placeholders

Two known causes:

1. **Missing `contents: write` permission.** Add it to the workflow permissions block.
2. **Concurrent run race.** Two simultaneous workflows tried to push to the same `images-branch` and the second `updateRef` lost the race. There is no retry currently. Workaround: serialize PR runs (e.g. `concurrency: group: ${{ github.ref }}`), or use a per-workflow `images-branch`.

### `Schema validation failed` from the formatter binary

Your raw-run JSON was produced by an older adapter than the formatter expects. Either upgrade your adapter, or pin `formatter-version` to a compatible version.

### Comment is showing partial markdown / "Report truncated"

GitHub caps comments at ~65 KB. The action truncates at the last newline before 55 KB and adds a "Report truncated" note. The full content is in the HTML artifact. If you see this routinely, consider splitting suites with [Multiple reports per PR](#multiple-reports-per-pr).

## FAQ

**Does this work on private repositories?**
Yes. No external services are involved — the action runs entirely inside GitHub Actions and uses only the repo's own `GITHUB_TOKEN`.

**Does this work for PRs from forks?**
The default `GITHUB_TOKEN` for fork PRs is read-only, so neither the comment nor the orphan-branch commit can be written. Common workarounds: run the comment step under `pull_request_target` (be aware of the [security implications](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/)), or use a workflow that gates on `github.event.pull_request.head.repo.full_name == github.repository`.

**Does this run my tests?**
No. The action surfaces the output of a reporter that has already run. See [Prerequisites](#prerequisites).

**Can I customize the comment template?**
Not currently. The header is configurable via `comment-title`; the body is the markdown produced by the formatter. If you need richer customization, you can read the markdown via the `markdown-report-path` output and post your own comment with `actions/github-script`.

**What permissions does `GITHUB_TOKEN` need?**
At minimum `pull-requests: write`. Add `contents: write` only if using `host-images: branch`. The action does not require any classic-PAT or app-token configuration.

**Will the orphan `images-branch` grow without bound?**
Yes — there is no automatic cleanup yet. Old `pr-*/` directories are safe to delete manually at any time (they are referenced by historical PR comments, but the comments degrade gracefully to broken-image icons). A cleanup recipe / retention input may land in a future release.

**Where do I report bugs or request features?**
[github.com/jagreehal/executable-stories-action/issues](https://github.com/jagreehal/executable-stories-action/issues)

## Supported frameworks

| Framework | Output type | Action config needed |
|---|---|---|
| Vitest | HTML + Markdown (via StoryReporter) | None |
| Jest | HTML + Markdown (via reporter) | None |
| Playwright | HTML + Markdown (via reporter) | None |
| Cypress | HTML + Markdown (via reporter) | None |
| pytest | Raw JSON | None |
| Go | Raw JSON | None |
| Rust | Raw JSON | None |
| Ruby (Minitest) | Raw JSON | None |
| JUnit 5 (Kotlin) | Raw JSON | None |
| xUnit (C#) | Raw JSON | None |

## License

[MIT](LICENSE)
