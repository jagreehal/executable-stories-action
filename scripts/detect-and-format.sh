#!/usr/bin/env bash
set -euo pipefail

HTML_PATH="${REPORT_DIR}/${OUTPUT_NAME}.html"
MD_PATH="${REPORT_DIR}/${OUTPUT_NAME}.md"
MODE="${MODE:-report}"

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
# Review mode: correlate a run JSON against the PR diff (Evidence Review).
# ---------------------------------------------------------------------------
if [[ "$MODE" == "review" ]]; then
  RUN_JSON="${RUN_JSON:-}"
  [[ -z "$RUN_JSON" ]] && RUN_JSON="$RAW_RUN"
  if [[ ! -f "$RUN_JSON" ]]; then
    echo "::error::review mode needs a run JSON. Looked for '${RUN_JSON}'."
    echo "::error::Set run-json to your raw or canonical run output (JS reporters can emit raw-run.json; non-JS adapters write .executable-stories/raw-run.json)."
    exit 1
  fi

  # Resolve the changed-files context: use a precomputed file if given,
  # otherwise derive it from the diff against the base ref.
  CF="${CHANGED_FILES:-}"
  if [[ -n "$CF" && -f "$CF" ]]; then
    echo "::notice::Using provided changed-files at ${CF}"
  else
    CF="$(mktemp)"
    BR="${BASE_REF:-}"
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
  GATE_ARGS=()
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
  CODE=$?
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
  exit 0
fi

# ---------------------------------------------------------------------------
# Report mode (default).
# ---------------------------------------------------------------------------

# Path 1: Pre-generated reports exist
if [[ -f "$HTML_PATH" && -f "$MD_PATH" ]]; then
  echo "::notice::Found pre-generated reports at ${REPORT_DIR}/"
  exit 0
fi

# Path 2: Raw run JSON exists — download binary and format
if [[ -f "$RAW_RUN" ]]; then
  echo "::notice::Found raw run JSON at ${RAW_RUN}, resolving formatter binary..."

  resolve_binary

  # Generate reports
  mkdir -p "$REPORT_DIR"
  "$BINARY_PATH" format "$RAW_RUN" \
    --format html,markdown \
    --output-dir "$REPORT_DIR" \
    --output-name "$OUTPUT_NAME"

  # Verify output
  if [[ ! -f "$HTML_PATH" || ! -f "$MD_PATH" ]]; then
    echo "::error::Formatter ran but expected output files not found at ${HTML_PATH} and ${MD_PATH}"
    exit 1
  fi

  echo "::notice::Reports generated at ${REPORT_DIR}/"
  exit 0
fi

# Neither found
echo "::error::No reports found at ${HTML_PATH} and no raw run JSON at ${RAW_RUN}."
echo "::error::Ensure your test runner generates executable-stories output."
echo "::error::JS/TS: configure StoryReporter with outputDir/outputName. Non-JS: check .executable-stories/raw-run.json exists after tests."
exit 1
