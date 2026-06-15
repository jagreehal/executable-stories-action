#!/usr/bin/env bash
set -euo pipefail

HTML_PATH="${REPORT_DIR}/${OUTPUT_NAME}.html"
MD_PATH="${REPORT_DIR}/${OUTPUT_NAME}.md"
MODE="${MODE:-report}"

echo "gate-failed=false" >> "${GITHUB_OUTPUT:-/dev/null}"

# ---------------------------------------------------------------------------
# Resolve the executable-stories binary into BINARY_PATH.
# Honours FORMATTER_BINARY (a prebuilt binary path) for dev/testing before a
# release exists; otherwise downloads the platform binary from GitHub Releases.
# ---------------------------------------------------------------------------
resolve_binary() {
  if [[ -n "${FORMATTER_BINARY:-}" ]]; then
    if [[ ! -f "$FORMATTER_BINARY" ]]; then
      echo "::error::formatter-binary set but not found: ${FORMATTER_BINARY}"
      exit 1
    fi
    chmod +x "$FORMATTER_BINARY"
    BINARY_PATH="$FORMATTER_BINARY"
    echo "::notice::Using provided formatter binary at ${FORMATTER_BINARY}"
    return
  fi

  # Determine platform binary name (tr for bash 3 compat on macOS)
  local OS ARCH BINARY REPO TAG DOWNLOAD_DIR
  OS=$(echo "$RUNNER_OS" | tr '[:upper:]' '[:lower:]')
  ARCH=$(echo "$RUNNER_ARCH" | tr '[:upper:]' '[:lower:]')

  case "$OS" in
    macos)  OS="darwin" ;;
    linux)  OS="linux" ;;
    windows) OS="windows" ;;
    *) echo "::error::Unsupported OS: ${RUNNER_OS}"; exit 1 ;;
  esac

  BINARY="executable-stories-${OS}-${ARCH}"
  [[ "$OS" == "windows" ]] && BINARY="${BINARY}.exe"

  REPO="jagreehal/executable-stories"
  if [[ "$FORMATTER_VERSION" == "latest" ]]; then
    TAG=$(gh release list --repo "$REPO" --limit 20 --json tagName --jq '[.[] | select(.tagName | startswith("executable-stories-formatters@"))][0].tagName')
    if [[ -z "$TAG" ]]; then
      echo "::error::Could not find a formatters release in ${REPO}. Ensure binaries are attached to releases."
      exit 1
    fi
  else
    TAG="executable-stories-formatters@${FORMATTER_VERSION}"
  fi

  echo "Downloading ${BINARY} from release ${TAG}..."
  DOWNLOAD_DIR=$(mktemp -d)
  gh release download "$TAG" \
    --repo "$REPO" \
    --pattern "$BINARY" \
    --dir "$DOWNLOAD_DIR"

  BINARY_PATH="${DOWNLOAD_DIR}/${BINARY}"
  chmod +x "$BINARY_PATH"
}

# ---------------------------------------------------------------------------
# MODE: report (default)
# ---------------------------------------------------------------------------
run_report() {
  # Path 1: Pre-generated reports exist
  if [[ -f "$HTML_PATH" && -f "$MD_PATH" ]]; then
    echo "::notice::Found pre-generated reports at ${REPORT_DIR}/"
    return
  fi

  # Path 2: Raw run JSON exists — download binary and format
  if [[ -f "$RAW_RUN" ]]; then
    echo "::notice::Found raw run JSON at ${RAW_RUN}, resolving formatter binary..."

    resolve_binary

    mkdir -p "$REPORT_DIR"
    "$BINARY_PATH" format "$RAW_RUN" \
      --format html,markdown \
      --output-dir "$REPORT_DIR" \
      --output-name "$OUTPUT_NAME"

    if [[ ! -f "$HTML_PATH" || ! -f "$MD_PATH" ]]; then
      echo "::error::Formatter ran but expected output files not found at ${HTML_PATH} and ${MD_PATH}"
      exit 1
    fi

    echo "::notice::Reports generated at ${REPORT_DIR}/"
    return
  fi

  # Neither found
  echo "::error::No reports found at ${HTML_PATH} and no raw run JSON at ${RAW_RUN}."
  echo "::error::Ensure your test runner generates executable-stories output."
  echo "::error::JS/TS: configure StoryReporter with outputDir/outputName. Non-JS: check .executable-stories/raw-run.json exists after tests."
  exit 1
}

# ---------------------------------------------------------------------------
# MODE: review — correlate a run JSON against the PR diff (Evidence Review)
# ---------------------------------------------------------------------------
run_review() {
  local RUN_JSON="${RUN_JSON:-}"
  [[ -z "$RUN_JSON" ]] && RUN_JSON="$RAW_RUN"
  if [[ ! -f "$RUN_JSON" ]]; then
    echo "::error::review mode needs a run JSON. Looked for '${RUN_JSON}'."
    echo "::error::Set run-json to your raw or canonical run output (JS reporters can emit raw-run.json; non-JS adapters write .executable-stories/raw-run.json)."
    exit 1
  fi

  # Resolve the changed-files context: use a precomputed file if given,
  # otherwise derive it from the diff against the base ref.
  local CF="${CHANGED_FILES:-}"
  if [[ -n "$CF" && -f "$CF" ]]; then
    echo "::notice::Using provided changed-files at ${CF}"
  else
    CF="$(mktemp)"
    local BR="${BASE_REF:-}"
    [[ -z "$BR" ]] && BR="${GITHUB_BASE_REF:-}"
    [[ -z "$BR" ]] && BR="main"
    echo "::notice::Computing changed files against '${BR}'..."
    git fetch --no-tags --depth=50 origin "$BR" >/dev/null 2>&1 || true
    if git rev-parse "origin/${BR}" >/dev/null 2>&1; then
      git diff --name-status "origin/${BR}...HEAD" > "$CF" 2>/dev/null \
        || git diff --name-status "origin/${BR}" HEAD > "$CF" 2>/dev/null \
        || : > "$CF"
    else
      git diff --name-status "${BR}...HEAD" > "$CF" 2>/dev/null || : > "$CF"
    fi
  fi

  resolve_binary

  mkdir -p "$REPORT_DIR"

  # Build optional gate flags
  local GATE_ARGS=()
  [[ -n "${FAIL_ON:-}" ]] && GATE_ARGS+=(--fail-on "$FAIL_ON")
  [[ -n "${MIN_EVIDENCE:-}" ]] && GATE_ARGS+=(--min-evidence "$MIN_EVIDENCE")

  # The review report is written before any gate is evaluated, so even when the
  # gate fails (exit 5) the report exists for the comment/artifact steps. We
  # capture the gate result and enforce it in a later step so the comment posts.
  set +e
  "$BINARY_PATH" review "$RUN_JSON" \
    --changed-files "$CF" \
    ${BASE_REF:+--base-ref "$BASE_REF"} \
    --output-dir "$REPORT_DIR" \
    --output-name "$OUTPUT_NAME" \
    ${GATE_ARGS[@]+"${GATE_ARGS[@]}"}
  local CODE=$?
  set -e

  if [[ "$CODE" -eq 5 ]]; then
    echo "gate-failed=true" >> "$GITHUB_OUTPUT"
    echo "::warning::Evidence Review gate failed; report generated, gate enforced after comment."
  elif [[ "$CODE" -ne 0 ]]; then
    echo "::error::review failed with exit code ${CODE}"
    exit "$CODE"
  fi

  if [[ ! -f "$HTML_PATH" || ! -f "$MD_PATH" ]]; then
    echo "::error::review ran but expected output files not found at ${HTML_PATH} and ${MD_PATH}"
    exit 1
  fi

  echo "::notice::Evidence Review generated at ${REPORT_DIR}/"
}

# ---------------------------------------------------------------------------
# MODE: gate-release
# ---------------------------------------------------------------------------
run_gate_release() {
  local DEV_RUN="${GATE_DEV_RUN:-}"
  if [[ -z "$DEV_RUN" ]]; then
    echo "::error::gate-release mode requires gate-dev-run (path to dev environment test run)"
    exit 1
  fi

  if [[ ! -f "$DEV_RUN" ]]; then
    echo "::error::Dev run file not found: ${DEV_RUN}"
    exit 1
  fi

  if [[ ! -f "$RAW_RUN" ]]; then
    echo "::error::RC run file not found: ${RAW_RUN}"
    exit 1
  fi

  resolve_binary

  # Build gate-release flags
  local FLAGS=(--format html,markdown --output-dir "$REPORT_DIR" --output-name "$OUTPUT_NAME")

  GATE_FAIL_ON_REGRESSION="${GATE_FAIL_ON_REGRESSION:-true}"
  GATE_FAIL_ON_REMOVAL="${GATE_FAIL_ON_REMOVAL:-true}"
  GATE_FAIL_ON_NEW="${GATE_FAIL_ON_NEW:-false}"

  # Gate-release subcommand enables --fail-on-regression and --fail-on-removal by default,
  # but we also support explicit overrides via inputs.

  if [[ "$GATE_FAIL_ON_REGRESSION" == "false" ]]; then
    # gate-release enables regression check by default; no way to disable yet except via policy
    echo "::warning::gate-fail-on-regression=false — regression check is always on in gate-release"
  fi
  if [[ "$GATE_FAIL_ON_REMOVAL" == "false" ]]; then
    echo "::warning::gate-fail-on-removal=false — removal check is always on in gate-release"
  fi
  if [[ "$GATE_FAIL_ON_NEW" == "true" ]]; then
    FLAGS+=(--fail-on-new)
  fi

  if [[ -n "${GATE_RELEASE_POLICY:-}" ]] && [[ -f "$GATE_RELEASE_POLICY" ]]; then
    FLAGS+=(--release-policy "$GATE_RELEASE_POLICY")
  fi

  echo "::group::Running release gate: dev=${DEV_RUN} rc=${RAW_RUN}"
  set +e
  "$BINARY_PATH" gate-release "$DEV_RUN" "$RAW_RUN" "${FLAGS[@]}"
  local EXIT_CODE=$?
  set -e
  echo "::endgroup::"

  if [[ $EXIT_CODE -eq 6 ]]; then
    echo "gate-failed=true" >> "$GITHUB_OUTPUT"
    echo "::error::Release gate failed. RC does not match dev baseline."
  elif [[ $EXIT_CODE -ne 0 ]]; then
    echo "::error::gate-release command failed with exit code ${EXIT_CODE}"
    exit $EXIT_CODE
  else
    echo "gate-failed=false" >> "$GITHUB_OUTPUT"
    echo "::notice::Release gate passed. RC matches dev baseline."
  fi
}

# ---------------------------------------------------------------------------
# MODE: deploy
# ---------------------------------------------------------------------------
run_deploy() {
  local ENV="${DEPLOY_ENV:-}"
  if [[ -z "$ENV" ]]; then
    echo "::error::deploy mode requires deploy-env (environment name)"
    exit 1
  fi

  if [[ ! -f "$RAW_RUN" ]]; then
    echo "::error::Raw run file not found: ${RAW_RUN}"
    exit 1
  fi

  resolve_binary

  local FLAGS=(--env "$ENV")
  if [[ -n "${DEPLOY_TAG:-}" ]]; then
    FLAGS+=(--tag "$DEPLOY_TAG")
  fi
  local LEDGER="${DEPLOY_LEDGER:-.executable-stories/deployments.json}"
  FLAGS+=(--ledger "$LEDGER")

  echo "::group::Recording deployment to ${ENV}"
  "$BINARY_PATH" deploy record "$RAW_RUN" "${FLAGS[@]}"
  echo "::endgroup::"

  echo "::notice::Deployment to ${ENV} recorded in ${LEDGER}"
  echo "deploy-ledger-path=${LEDGER}" >> "$GITHUB_OUTPUT"
  echo "::notice::Persist ${LEDGER} as an artifact, cache, or committed file if later jobs should compare environments."

  # Also show current status
  echo "::group::Deployment status"
  "$BINARY_PATH" deploy status --ledger "$LEDGER" || true
  echo "::endgroup::"
}

# ---------------------------------------------------------------------------
# MODE: portal — build the Living-Docs Portal (self-hostable static site)
# ---------------------------------------------------------------------------
# Generates the portal content from a raw run into an Astro site, optionally
# builds it to a host-agnostic static `dist/`, and exposes the path so the
# composite action can upload it as an artifact (deploy anywhere) and/or publish
# it to GitHub Pages.
run_portal() {
  if [[ ! -f "$RAW_RUN" ]]; then
    echo "::error::portal mode requires a raw run JSON. Not found: ${RAW_RUN}"
    echo "::error::Ensure your test runner wrote .executable-stories/raw-run.json (or set raw-run)."
    exit 1
  fi

  local SITE_DIR="${PORTAL_SITE_DIR:-.}"
  if [[ ! -d "$SITE_DIR" ]]; then
    echo "::error::portal-site-dir does not exist: ${SITE_DIR}. Scaffold an Astro site first (executable-stories init-astro)."
    exit 1
  fi

  resolve_binary

  local FLAGS=("$RAW_RUN" --site-dir "$SITE_DIR")
  # The portal is the audience-aware surface, so the split is on by default here
  # (unlike plain `build-docs`, which stays backward-compatible with flat URLs).
  if [[ "${PORTAL_AUDIENCE_SPLIT:-true}" == "true" ]]; then
    FLAGS+=(--audience-split)
  fi
  if [[ -n "${PORTAL_BASELINE:-}" ]]; then
    # A baseline that was asked for but is missing is a hard error here too — the
    # same contract as build-docs. Downgrading it to a warning would let a typo'd
    # path produce a green run that silently drops the what's-changed page. On the
    # first run (no prior report yet) simply leave portal-baseline unset, or guard
    # it in the workflow (e.g. only set it after a successful artifact download).
    if [[ ! -f "$PORTAL_BASELINE" ]]; then
      echo "::error::portal-baseline not found: ${PORTAL_BASELINE}"
      echo "::error::Fix the path, or leave portal-baseline unset on the first run (before any baseline exists)."
      exit 1
    fi
    FLAGS+=(--baseline "$PORTAL_BASELINE")
    echo "::notice::Computing what's-changed against baseline ${PORTAL_BASELINE}"
  fi

  echo "::group::Generating portal content into ${SITE_DIR}"
  "$BINARY_PATH" build-docs "${FLAGS[@]}"
  echo "::endgroup::"

  local STORY_REPORT_PATH="${SITE_DIR%/}/public/stories/story-report.json"
  echo "portal-story-report-path=${STORY_REPORT_PATH}" >> "$GITHUB_OUTPUT"
  echo "::notice::Portal ownership model: keep ${SITE_DIR}/src/content/docs/{guides,notes,adr,runbooks,...} in git; treat ${SITE_DIR}/src/content/docs/stories and ${SITE_DIR}/public/stories as generated output."

  local DIST_DIR="${SITE_DIR%/}/${PORTAL_DIST_DIR:-dist}"

  if [[ "${PORTAL_BUILD:-true}" == "true" ]]; then
    local BUILD_CMD="${PORTAL_BUILD_COMMAND:-npm run build}"
    echo "::group::Building static site (${BUILD_CMD}) in ${SITE_DIR}"
    set +e
    ( cd "$SITE_DIR" && eval "$BUILD_CMD" )
    local BUILD_EXIT=$?
    set -e
    echo "::endgroup::"
    if [[ $BUILD_EXIT -ne 0 ]]; then
      echo "::error::Site build failed (${BUILD_CMD}). Did the job run 'npm ci' in ${SITE_DIR} first?"
      exit $BUILD_EXIT
    fi
    if [[ ! -d "$DIST_DIR" ]]; then
      echo "::error::Build finished but ${DIST_DIR} not found. Set portal-dist-dir to your build output."
      exit 1
    fi
    echo "portal-output-path=${DIST_DIR}" >> "$GITHUB_OUTPUT"
    echo "::notice::Portal built → ${DIST_DIR} (host-agnostic static site)"
  else
    # No build: hand back the prepared site dir so the consumer builds it elsewhere.
    echo "portal-output-path=${SITE_DIR}" >> "$GITHUB_OUTPUT"
    echo "::notice::Portal content generated → ${SITE_DIR} (build skipped; portal-build=false)"
  fi
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
case "$MODE" in
  report)
    run_report
    ;;
  review)
    run_review
    ;;
  gate-release)
    run_gate_release
    ;;
  deploy)
    run_deploy
    ;;
  portal)
    run_portal
    ;;
  *)
    echo "::error::Unknown mode: ${MODE}. Supported: report, review, gate-release, deploy, portal"
    exit 1
    ;;
esac
