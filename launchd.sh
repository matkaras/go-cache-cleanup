#!/usr/bin/env bash

set -euo pipefail

readonly PROG="${0##*/}"
readonly LABEL="com.matkaras.go-cache-trim"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly USER_HOME="${HOME:?HOME is not set}"
readonly PLIST_PATH="${USER_HOME}/Library/LaunchAgents/${LABEL}.plist"
readonly BIN_LINK="${USER_HOME}/.local/bin/go-cache-trim"
readonly SKILL_LINK="${USER_HOME}/.claude/skills/go-cache-cleanup"
readonly LOG_DIR="${USER_HOME}/.local/state/go-cache-trim"
readonly MIN_FREE_GIB="${MIN_FREE_GIB:-10}"
DOMAIN="gui/$(id -u)"
readonly DOMAIN
readonly SERVICE="${DOMAIN}/${LABEL}"

usage() {
  cat << EOF
Usage: ${PROG} COMMAND
Manage the Go build cache trim LaunchAgent and the go-cache-cleanup skill.

Commands:
  install       link the script and skill, write the plist, and start the agent
  uninstall     unload the agent and remove the plist and links
  status        print the launchd status and the log tail
  print         print the generated plist without installing it
  -h, --help    display this help and exit

Environment:
  MIN_FREE_GIB  free space to keep on /System/Volumes/Data (default: 10)

Exit status:
  0  success
  1  operational error
  2  usage error
EOF
}

log() { echo "${PROG}: $*" >&2; }
fatal() {
  echo "${PROG}: ERROR: $1" >&2
  exit "${2:-1}"
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf '%s' "${value}"
}

go_dir() {
  local go_path
  go_path="$(command -v go)" || fatal "go was not found in PATH"
  dirname -- "${go_path}"
}

render_plist() {
  local path_value
  path_value="$(xml_escape "$(go_dir):/usr/bin:/bin:/usr/sbin:/sbin")"
  cat << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(xml_escape "${BIN_LINK}")</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${path_value}</string>
    <key>MIN_FREE_GIB</key>
    <string>$(xml_escape "${MIN_FREE_GIB}")</string>
  </dict>
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Minute</key><integer>0</integer></dict>
    <dict><key>Minute</key><integer>15</integer></dict>
    <dict><key>Minute</key><integer>30</integer></dict>
    <dict><key>Minute</key><integer>45</integer></dict>
  </array>
  <key>LowPriorityIO</key>
  <true/>
  <key>Nice</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>$(xml_escape "${LOG_DIR}/trim.log")</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "${LOG_DIR}/trim.log")</string>
</dict>
</plist>
EOF
}

# Link target to source. An existing link is replaced; a real file or
# directory is left alone so local edits are never lost.
link() {
  local source="$1" target="$2"
  if [[ -e "${target}" && ! -L "${target}" ]]; then
    fatal "${target} exists and is not a link; move it away and run install again"
  fi
  mkdir -p "$(dirname -- "${target}")"
  ln -sfn "${source}" "${target}"
  log "linked ${target} -> ${source}"
}

unload() {
  if launchctl print "${SERVICE}" > /dev/null 2>&1; then
    launchctl bootout "${SERVICE}"
  fi
}

install() {
  [[ "$(uname -s)" == "Darwin" ]] || fatal "this tool runs only on macOS"
  link "${SCRIPT_DIR}/bin/go-cache-trim" "${BIN_LINK}"
  link "${SCRIPT_DIR}/skills/go-cache-cleanup" "${SKILL_LINK}"
  mkdir -p "${LOG_DIR}" "$(dirname -- "${PLIST_PATH}")"
  render_plist > "${PLIST_PATH}"
  plutil -lint "${PLIST_PATH}" > /dev/null
  unload
  launchctl bootstrap "${DOMAIN}" "${PLIST_PATH}"
  launchctl kickstart "${SERVICE}"
  log "installed ${PLIST_PATH}; first run logged to ${LOG_DIR}/trim.log"
}

uninstall() {
  unload
  rm -f "${PLIST_PATH}"
  [[ -L "${BIN_LINK}" ]] && rm -f "${BIN_LINK}"
  [[ -L "${SKILL_LINK}" ]] && rm -f "${SKILL_LINK}"
  log "uninstalled; the log stays in ${LOG_DIR}"
}

status() {
  launchctl print "${SERVICE}" 2> /dev/null | grep -E 'state =|runs =|last exit code' || log "${LABEL} is not loaded"
  tail -n 5 "${LOG_DIR}/trim.log" 2> /dev/null || true
}

main() {
  [[ $# -eq 1 ]] || {
    usage >&2
    exit 2
  }
  case "$1" in
    install) install ;;
    uninstall) uninstall ;;
    status) status ;;
    print) render_plist ;;
    -h | --help) usage ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
