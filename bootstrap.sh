#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="${HOME}/dotfiles"
REPOSITORY="Matt-Cain/dotfiles"
REPOSITORY_URL="https://github.com/${REPOSITORY}.git"

BIN_DIR="${HOME}/bin"
DOTFILES_BIN="${BIN_DIR}/dotfiles"
DOTFILES_COMMAND="${DOTFILES_DIR}/scripts/bin/dotfiles"
ZSHRC="${HOME}/.zshrc"

# Colors are enabled only when stdout is an interactive terminal.
if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
  BOLD=$'\033[1m'
  BLUE=$'\033[34m'
  CYAN=$'\033[36m'
  GREEN=$'\033[32m'
  RED=$'\033[31m'
  YELLOW=$'\033[33m'
  DIM=$'\033[2m'
  RESET=$'\033[0m'
else
  BOLD=''
  BLUE=''
  CYAN=''
  GREEN=''
  RED=''
  YELLOW=''
  DIM=''
  RESET=''
fi

log_section() {
  printf '\n%s◆ %s%s\n' "$BLUE" "$1" "$RESET"
}

log_info() {
  printf '  %s→%s %s\n' "$CYAN" "$RESET" "$1"
}

log_success() {
  printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"
}

log_skip() {
  printf '  %s↷%s %s\n' "$YELLOW" "$RESET" "$1"
}

log_error() {
  printf '  %s✗%s %s\n' "$RED" "$RESET" "$1" >&2
}

die() {
  log_error "$1"
  exit 1
}

# Check the active PATH rather than inferring it from shell config files.
path_contains_bin() {
  local entry
  local -a path_entries=()

  IFS=: read -r -a path_entries <<<"${PATH:-}"

  for entry in "${path_entries[@]}"; do
    if [[ "${entry%/}" == "${BIN_DIR%/}" ]]; then
      return 0
    fi
  done

  return 1
}

# Resolve a path through chains of absolute or relative symlinks.
resolve_path() {
  local path="$1"
  local parent
  local target

  while [[ -L "$path" ]]; do
    parent="$(cd -P "$(dirname "$path")" >/dev/null 2>&1 && pwd)" ||
      return 1

    target="$(readlink "$path")" || return 1

    if [[ "$target" = /* ]]; then
      path="$target"
    else
      path="${parent}/${target}"
    fi
  done

  parent="$(cd -P "$(dirname "$path")" >/dev/null 2>&1 && pwd)" ||
    return 1

  printf '%s/%s\n' "$parent" "$(basename "$path")"
}

printf '\n%s╭──────────────────────────────────────╮%s\n' "$BOLD" "$RESET"
printf '%s│         Dotfiles bootstrap           │%s\n' "$BOLD" "$RESET"
printf '%s╰──────────────────────────────────────╯%s\n' "$BOLD" "$RESET"

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

log_section "Prerequisites"

if command -v git >/dev/null 2>&1; then
  log_success "Git is available"
else
  die "Git is required. On macOS, install Xcode Command Line Tools."
fi

# ---------------------------------------------------------------------------
# Repository
# ---------------------------------------------------------------------------

log_section "Repository"

if [[ -d "${DOTFILES_DIR}/.git" || -f "${DOTFILES_DIR}/.git" ]]; then
  log_skip "Repository already exists: ${DOTFILES_DIR}"
elif [[ -e "$DOTFILES_DIR" || -L "$DOTFILES_DIR" ]]; then
  die "${DOTFILES_DIR} already exists but is not a Git repository."
else
  log_info "Cloning ${REPOSITORY}..."
  git clone "$REPOSITORY_URL" "$DOTFILES_DIR"
  log_success "Cloned repository to ${DOTFILES_DIR}"
fi

# The command must already exist and be executable in the repository.
[[ -f "$DOTFILES_COMMAND" && -x "$DOTFILES_COMMAND" ]] ||
  die "Repository is missing an executable dotfiles command: ${DOTFILES_COMMAND}"

# ---------------------------------------------------------------------------
# User bin directory
# ---------------------------------------------------------------------------

log_section "User bin directory"

if [[ -d "$BIN_DIR" ]]; then
  log_skip "Directory already exists: ${BIN_DIR}"
elif [[ -e "$BIN_DIR" || -L "$BIN_DIR" ]]; then
  die "${BIN_DIR} exists but is not a directory."
else
  mkdir -p "$BIN_DIR"
  log_success "Created directory: ${BIN_DIR}"
fi

# ---------------------------------------------------------------------------
# Command symlink
# ---------------------------------------------------------------------------

log_section "Command symlink"

if [[ -L "$DOTFILES_BIN" ]]; then
  existing_target="$(readlink "$DOTFILES_BIN")"

  if [[ "$existing_target" == "$DOTFILES_COMMAND" ]]; then
    log_skip "Symlink is already correct"
  else
    ln -sfn "$DOTFILES_COMMAND" "$DOTFILES_BIN"
    log_success "Updated symlink to the repository command"
  fi
elif [[ -e "$DOTFILES_BIN" ]]; then
  die "${DOTFILES_BIN} exists and is not a symlink; leaving it untouched."
else
  ln -s "$DOTFILES_COMMAND" "$DOTFILES_BIN"
  log_success "Created symlink: ${DOTFILES_BIN} → repository command"
fi

# ---------------------------------------------------------------------------
# Zsh PATH
# ---------------------------------------------------------------------------

log_section "Zsh PATH"

if path_contains_bin; then
  log_skip "~/bin is already in the current PATH"
else
  log_info "~/bin is missing from the current PATH; checking Zsh config"

  if [[ -L "$ZSHRC" ]]; then
    log_info "Following Zsh config symlink: ${ZSHRC}"
  fi

  ZSHRC_FILE="$(resolve_path "$ZSHRC")" ||
    die "Unable to resolve ${ZSHRC}"

  [[ ! -d "$ZSHRC_FILE" ]] ||
    die "Resolved Zsh config is a directory: ${ZSHRC_FILE}"

  if [[ -f "$ZSHRC_FILE" ]]; then
    log_skip "Zsh config already exists"
  else
    touch "$ZSHRC_FILE"
    log_success "Created Zsh config: ${ZSHRC_FILE}"
  fi

  if grep -Eq '^[[:space:]]*export[[:space:]]+PATH=.*[$]HOME/bin' "$ZSHRC_FILE"; then
    log_skip "~/bin is already configured in the Zsh config"
  else
    cat >>"$ZSHRC_FILE" <<'ZSHRC'

# Added by dotfiles bootstrap.
export PATH="$HOME/bin:$PATH"
ZSHRC

    log_success "Added ~/bin to PATH in ${ZSHRC_FILE}"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%s╭──────────────────────────────────────╮%s\n' "$GREEN" "$RESET"
printf '%s│       Bootstrap completed ✓          │%s\n' "$GREEN" "$RESET"
printf '%s╰──────────────────────────────────────╯%s\n' "$GREEN" "$RESET"

printf '\n'
printf '%sNo installation has been run.%s\n' "$BOLD" "$RESET"
printf '\n'
printf 'Next steps:\n'
printf '  %s1.%s Reload your shell configuration:\n' "$CYAN" "$RESET"
printf '     source ~/.zshrc\n'
printf '\n'
printf '  %s2.%s Preview the planned changes:\n' "$CYAN" "$RESET"
printf '     dotfiles dry-run\n'
printf '\n'
printf '  %s3.%s Apply when you are ready:\n' "$CYAN" "$RESET"
printf '     dotfiles install\n'
printf '\n'
