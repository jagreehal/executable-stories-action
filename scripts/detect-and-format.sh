#!/usr/bin/env bash
set -euo pipefail

HTML_PATH="${REPORT_DIR}/${OUTPUT_NAME}.html"
MD_PATH="${REPORT_DIR}/${OUTPUT_NAME}.md"

# Path 1: Pre-generated reports exist
if [[ -f "$HTML_PATH" && -f "$MD_PATH" ]]; then
  echo "::notice::Found pre-generated reports at ${REPORT_DIR}/"
  exit 0
fi

# Path 2: Raw run JSON exists — download binary and format
if [[ -f "$RAW_RUN" ]]; then
  echo "::notice::Found raw run JSON at ${RAW_RUN}, downloading formatter binary..."

  # Determine platform binary name (tr for bash 3 compat on macOS)
  OS=$(echo "$RUNNER_OS" | tr '[:upper:]' '[:lower:]')
  ARCH=$(echo "$RUNNER_ARCH" | tr '[:upper:]' '[:lower:]')

  # Map GitHub runner OS names to binary names
  case "$OS" in
    macos)  OS="darwin" ;;
    linux)  OS="linux" ;;
    windows) OS="windows" ;;
    *) echo "::error::Unsupported OS: ${RUNNER_OS}"; exit 1 ;;
  esac

  BINARY="executable-stories-${OS}-${ARCH}"
  [[ "$OS" == "windows" ]] && BINARY="${BINARY}.exe"

  # Resolve download URL from GitHub Releases
  REPO="jagreehal/executable-stories"
  if [[ "$FORMATTER_VERSION" == "latest" ]]; then
    # Find the latest formatters release tag
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
