#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="${HOME}/dotfiles"
REPOSITORY="Matt-Cain/dotfiles"
REPOSITORY_URL="git@github.com:${REPOSITORY}.git"

BIN_DIR="${HOME}/bin"
DOTFILES_BIN="${BIN_DIR}/dotfiles"
DOTFILES_COMMAND="${DOTFILES_DIR}/scripts/bin/dotfiles"
GITCONFIG_LOCAL="${HOME}/.gitconfig.local"
ZPROFILE="${HOME}/.zprofile"
ZSHRC="${HOME}/.zshrc"

HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
BOOTSTRAP_URL="https://raw.githubusercontent.com/Matt-Cain/dotfile-bootstrap/main/bootstrap.sh"

# Colors are enabled only when stdout is an interactive terminal.
if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
  BOLD=$'\033[1m'
  BLUE=$'\033[34m'
  CYAN=$'\033[36m'
  GREEN=$'\033[32m'
  RED=$'\033[31m'
  YELLOW=$'\033[33m'
  RESET=$'\033[0m'
else
  BOLD=''
  BLUE=''
  CYAN=''
  GREEN=''
  RED=''
  YELLOW=''
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

require_interactive_terminal() {
  [[ -t 0 && -t 1 ]] ||
    die "An interactive terminal is required. Run: bash <(curl -fsSL ${BOOTSTRAP_URL})"
}

# Check the active PATH rather than inferring it from shell configuration.
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

# Find Homebrew even when its prefix is not yet in PATH.
find_brew() {
  local brew_path

  brew_path="$(type -P brew || true)"

  if [[ -n "$brew_path" ]]; then
    printf '%s\n' "$brew_path"
    return 0
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    printf '%s\n' /opt/homebrew/bin/brew
    return 0
  fi

  if [[ -x /usr/local/bin/brew ]]; then
    printf '%s\n' /usr/local/bin/brew
    return 0
  fi

  return 1
}

# Resolve chains of absolute or relative symlinks.
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

ensure_homebrew_shellenv() {
  local config_file
  local brew_bin_quoted

  if [[ -L "$ZPROFILE" ]]; then
    log_info "Following Zsh login config symlink: ${ZPROFILE}"
  fi

  config_file="$(resolve_path "$ZPROFILE")" ||
    die "Unable to resolve ${ZPROFILE}"

  [[ ! -d "$config_file" ]] ||
    die "Resolved Zsh login config is a directory: ${config_file}"

  if [[ -f "$config_file" ]]; then
    log_skip "Zsh login config already exists"
  else
    touch "$config_file"
    log_success "Created Zsh login config"
  fi

  if grep -Eq '^[[:space:]]*eval[[:space:]].*brew.*shellenv' "$config_file"; then
    log_skip "Homebrew shellenv is already configured"
    return 0
  fi

  printf -v brew_bin_quoted '%q' "$BREW_BIN"

  {
    printf '\n# Added by dotfiles bootstrap.\n'
    printf 'eval "$(%s shellenv)"\n' "$brew_bin_quoted"
  } >>"$config_file"

  log_success "Added Homebrew shellenv to ${config_file}"
}

ensure_dotbot() {
  local brew_prefix
  local dotbot_bin

  log_section "Dotbot"

  if "$BREW_BIN" list --formula dotbot >/dev/null 2>&1; then
    log_skip "Dotbot is already installed with Homebrew"
  else
    log_info "Installing Dotbot with Homebrew..."
    "$BREW_BIN" install dotbot ||
      die "Could not install Dotbot with Homebrew."
  fi

  brew_prefix="$("$BREW_BIN" --prefix)" ||
    die "Could not determine the Homebrew prefix."
  dotbot_bin="${brew_prefix}/bin/dotbot"

  [[ -x "$dotbot_bin" ]] ||
    die "Dotbot was installed, but its executable is missing: ${dotbot_bin}"

  "$dotbot_bin" --help >/dev/null 2>&1 ||
    die "Dotbot is installed, but its executable failed to run: ${dotbot_bin}"

  log_success "Dotbot is installed and ready for dry runs"
}

# Preserve machine-specific Git identity independently of the managed .gitconfig.
setup_git_identity() {
  local existing_local_name
  local existing_local_email
  local existing_global_name
  local existing_global_email
  local git_name
  local git_email
  local github_profile_name
  local github_login
  local github_primary_email

  if [[ -L "$GITCONFIG_LOCAL" && ! -e "$GITCONFIG_LOCAL" ]]; then
    die "${GITCONFIG_LOCAL} is a broken symlink."
  fi

  if [[ -e "$GITCONFIG_LOCAL" && ! -f "$GITCONFIG_LOCAL" ]]; then
    die "${GITCONFIG_LOCAL} exists but is not a file."
  fi

  existing_local_name="$(git config --file "$GITCONFIG_LOCAL" --get user.name 2>/dev/null || true)"
  existing_local_email="$(git config --file "$GITCONFIG_LOCAL" --get user.email 2>/dev/null || true)"
  existing_global_name="$(git config --global --get user.name 2>/dev/null || true)"
  existing_global_email="$(git config --global --get user.email 2>/dev/null || true)"

  git_name="${existing_local_name:-$existing_global_name}"
  git_email="${existing_local_email:-$existing_global_email}"

  if [[ -n "$existing_local_name" && -n "$existing_local_email" ]]; then
    log_skip "Git name and email are already configured in ~/.gitconfig.local"
    return 0
  fi

  # Preserve an existing identity first. If the name is missing, use the
  # GitHub profile name, falling back to the account login when no name is set.
  if [[ -z "$git_name" ]]; then
    github_profile_name="$(gh api user --jq '.name // empty' 2>/dev/null || true)"

    if [[ -n "$github_profile_name" ]]; then
      git_name="$github_profile_name"
      log_success "Using GitHub profile name for Git identity"
    else
      github_login="$(get_github_username || true)"

      if [[ -n "$github_login" ]]; then
        git_name="$github_login"
        log_info "GitHub profile has no display name; using @${github_login}"
      fi
    fi
  elif [[ -n "$existing_local_name" ]]; then
    log_skip "Preserving existing local Git name"
  else
    log_info "Reusing existing global Git name"
  fi

  if [[ -z "$git_email" ]]; then
    if [[ -n "$existing_local_email" ]]; then
      log_skip "Preserving existing local Git email"
    elif [[ -n "$existing_global_email" ]]; then
      log_info "Reusing existing global Git email"
    else
      log_info "Looking up the primary verified GitHub email..."
      github_primary_email="$(
        gh api user/emails \
          --jq 'map(select(.primary == true and .verified == true)) | .[0].email // empty' \
          2>/dev/null || true
      )"

      # The email endpoint needs the user:email OAuth scope. Request it only
      # when the current credentials cannot provide the primary verified email.
      if [[ -z "$github_primary_email" ]]; then
        require_interactive_terminal
        log_info "GitHub needs permission to read your email addresses."

        if gh auth refresh --hostname github.com --scopes user:email; then
          github_primary_email="$(
            gh api user/emails \
              --jq 'map(select(.primary == true and .verified == true)) | .[0].email // empty' \
              2>/dev/null || true
          )"
        else
          log_info "Could not authorize GitHub email access; you'll be asked for an email if needed."
        fi
      fi

      if [[ -n "$github_primary_email" ]]; then
        git_email="$github_primary_email"
        log_success "Using primary verified GitHub email for Git identity"
      fi
    fi
  fi

  if [[ -z "$git_name" || -z "$git_email" ]]; then
    require_interactive_terminal
  fi

  if [[ -z "$git_name" ]]; then
    read -r -p '  Git author name: ' git_name || die "Could not read Git author name."
    [[ -n "$git_name" ]] || die "A Git author name is required."
  fi

  if [[ -z "$git_email" ]]; then
    read -r -p '  Git author email: ' git_email || die "Could not read Git author email."
    [[ -n "$git_email" ]] || die "A Git author email is required."
  fi

  if [[ ! -e "$GITCONFIG_LOCAL" ]]; then
    (umask 077 && : >"$GITCONFIG_LOCAL") ||
      die "Could not create ${GITCONFIG_LOCAL}"

    log_success "Created ~/.gitconfig.local"
  fi

  if [[ "$existing_local_name" != "$git_name" ]]; then
    git config --file "$GITCONFIG_LOCAL" user.name "$git_name" ||
      die "Could not save the Git author name."

    log_success "Saved Git author name"
  fi

  if [[ "$existing_local_email" != "$git_email" ]]; then
    git config --file "$GITCONFIG_LOCAL" user.email "$git_email" ||
      die "Could not save the Git author email."

    log_success "Saved Git author email"
  fi
}

get_github_username() {
  gh api user --jq '.login' 2>/dev/null
}

has_repository_access() {
  gh repo view "$REPOSITORY" --json nameWithOwner >/dev/null 2>&1
}

prefer_ssh_for_github() {
  local current_protocol

  current_protocol="$(gh config get git_protocol --host github.com 2>/dev/null || true)"

  if [[ "$current_protocol" == "ssh" ]]; then
    log_skip "GitHub CLI already prefers SSH"
  else
    gh config set git_protocol ssh --host github.com ||
      die "Could not configure GitHub CLI to prefer SSH."

    log_success "Configured GitHub CLI to prefer SSH"
  fi
}

login_to_github_with_ssh() {
  require_interactive_terminal

  log_info "Starting GitHub browser login with SSH Git access..."

  gh auth login --hostname github.com --git-protocol ssh --scopes user:email --web ||
    die "GitHub login failed. Resolve the reported issue and rerun bootstrap."
}

ensure_github_access() {
  local current_user
  local previous_user
  local action

  log_section "GitHub authentication"

  if gh auth status --hostname github.com >/dev/null 2>&1; then
    current_user="$(get_github_username || true)"

    if [[ -n "$current_user" ]]; then
      log_skip "Already authenticated as @${current_user}"
    else
      log_skip "GitHub CLI already has an authenticated account"
    fi
  else
    login_to_github_with_ssh
    gh auth status --hostname github.com >/dev/null 2>&1 ||
      die "GitHub authentication could not be verified."
  fi

  prefer_ssh_for_github

  while ! has_repository_access; do
    current_user="$(get_github_username || true)"

    if [[ -n "$current_user" ]]; then
      log_error "The active GitHub account @${current_user} cannot access ${REPOSITORY}."
    else
      log_error "Could not verify access to ${REPOSITORY} with the active GitHub account."
    fi

    require_interactive_terminal

    printf '  Choose how to continue:\n'
    printf '    %s[L]%s Log into another GitHub account\n' "$CYAN" "$RESET"
    printf '    %s[S]%s Switch to an already-authenticated account\n' "$CYAN" "$RESET"
    printf '    %s[Q]%s Quit bootstrap\n' "$CYAN" "$RESET"

    read -r -p '  Choice [L/S/Q]: ' action || die "Could not read account choice."

    case "$action" in
    [Ll])
      previous_user="$current_user"
      login_to_github_with_ssh

      current_user="$(get_github_username || true)"

      # Login can add an account without making it the active account.
      # If so, let gh select the intended account before checking access again.
      if [[ -n "$previous_user" && "$current_user" == "$previous_user" ]]; then
        log_info "Choose the account to use for this repository."
        gh auth switch --hostname github.com ||
          die "Could not switch GitHub accounts. Run 'gh auth status' to inspect configured accounts."
      fi
      ;;

    [Ss])
      if ! gh auth switch --hostname github.com; then
        log_error "Could not switch accounts. Try logging into another account instead."
        continue
      fi
      ;;

    [Qq] | '')
      die "Bootstrap cancelled. Grant the selected account access to ${REPOSITORY}, then rerun."
      ;;

    *)
      log_info "Choose L, S, or Q."
      continue
      ;;
    esac

    prefer_ssh_for_github
  done

  current_user="$(get_github_username || true)"

  if [[ -n "$current_user" ]]; then
    log_success "Repository access confirmed for @${current_user}"
  else
    log_success "Repository access confirmed"
  fi
}

verify_ssh_repository_access() {
  log_section "SSH access"
  log_info "Checking SSH access to ${REPOSITORY}..."

  if git ls-remote "$REPOSITORY_URL" HEAD >/dev/null; then
    log_success "SSH access to the private repository works"
  else
    die "GitHub API access works, but SSH access failed. Ensure an SSH key for an account with repository access is loaded and registered with GitHub, then rerun bootstrap. If this machine has no SSH key, gh auth login --hostname github.com --git-protocol ssh --web can guide key setup during authentication."
  fi
}

# ---------------------------------------------------------------------------
# Welcome
# ---------------------------------------------------------------------------

printf '\n%s╭──────────────────────────────────────╮%s\n' "$BOLD" "$RESET"
printf '%s│         Dotfiles bootstrap           │%s\n' "$BOLD" "$RESET"
printf '%s╰──────────────────────────────────────╯%s\n' "$BOLD" "$RESET"

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

log_section "Prerequisites"

[[ "$(uname -s)" == "Darwin" ]] ||
  die "This bootstrap is intended for macOS."

command -v curl >/dev/null 2>&1 ||
  die "curl is required to install Homebrew."

log_success "macOS and curl are available"

if command -v xcode-select >/dev/null 2>&1 && xcode-select -p >/dev/null 2>&1; then
  log_success "Xcode Command Line Tools are available"
else
  require_interactive_terminal

  log_info "Requesting Xcode Command Line Tools installation..."
  xcode-select --install || true

  die "Finish the Command Line Tools installation, then rerun bootstrap."
fi

command -v git >/dev/null 2>&1 ||
  die "Git is unavailable. Complete the Command Line Tools installation and rerun bootstrap."

log_success "Git is available"

# ---------------------------------------------------------------------------
# Homebrew
# ---------------------------------------------------------------------------

log_section "Homebrew"

BREW_BIN="$(find_brew || true)"

if [[ -n "$BREW_BIN" ]]; then
  log_skip "Homebrew is already installed"
else
  require_interactive_terminal

  installer="$(mktemp "${TMPDIR:-/tmp}/homebrew-install.XXXXXX")" ||
    die "Unable to create a temporary installer file."

  log_info "Downloading the official Homebrew installer..."

  if ! curl -fsSL "$HOMEBREW_INSTALL_URL" -o "$installer"; then
    rm -f "$installer"
    die "Could not download the Homebrew installer."
  fi

  log_info "Running Homebrew installer..."

  if ! /bin/bash "$installer"; then
    rm -f "$installer"
    die "Homebrew installation failed. Resolve the reported issue and rerun bootstrap."
  fi

  rm -f "$installer"

  BREW_BIN="$(find_brew || true)"
  [[ -n "$BREW_BIN" ]] ||
    die "Homebrew finished installing, but brew could not be found."

  log_success "Homebrew installed"
fi

BREW_SHELLENV="$("$BREW_BIN" shellenv)" ||
  die "Unable to initialize Homebrew."

eval "$BREW_SHELLENV"
log_success "Homebrew is ready"

ensure_homebrew_shellenv
ensure_dotbot

# ---------------------------------------------------------------------------
# GitHub CLI
# ---------------------------------------------------------------------------

log_section "GitHub CLI"

if command -v gh >/dev/null 2>&1; then
  log_skip "GitHub CLI is already installed"
else
  log_info "Installing GitHub CLI with Homebrew..."

  "$BREW_BIN" install gh ||
    die "Could not install GitHub CLI with Homebrew."

  log_success "GitHub CLI installed"
fi

# ---------------------------------------------------------------------------
# GitHub authentication and SSH
# ---------------------------------------------------------------------------

ensure_github_access
verify_ssh_repository_access

# ---------------------------------------------------------------------------
# Repository
# ---------------------------------------------------------------------------

log_section "Repository"

if [[ -d "${DOTFILES_DIR}/.git" || -f "${DOTFILES_DIR}/.git" ]]; then
  log_skip "Repository already exists: ${DOTFILES_DIR}"
elif [[ -e "$DOTFILES_DIR" || -L "$DOTFILES_DIR" ]]; then
  die "${DOTFILES_DIR} already exists but is not a Git repository."
else
  log_info "Cloning ${REPOSITORY} over SSH..."

  if ! git clone "$REPOSITORY_URL" "$DOTFILES_DIR"; then
    die "Could not clone ${REPOSITORY} over SSH. Check your SSH key and repository access, then rerun bootstrap."
  fi

  log_success "Cloned repository to ${DOTFILES_DIR}"
fi

[[ -f "$DOTFILES_COMMAND" && -x "$DOTFILES_COMMAND" ]] ||
  die "Repository is missing an executable dotfiles command: ${DOTFILES_COMMAND}"

# ---------------------------------------------------------------------------
# Local Git identity
# ---------------------------------------------------------------------------

log_section "Git identity"

setup_git_identity

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
    rm "$DOTFILES_BIN"
    ln -s "$DOTFILES_COMMAND" "$DOTFILES_BIN"
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
    log_success "Created Zsh config"
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
printf '%sHomebrew, Dotbot, GitHub authentication, SSH access, and local Git identity are ready.%s\n' "$BOLD" "$RESET"
printf '%sDotbot has not been run; the dotfiles configuration has not been applied.%s\n' "$BOLD" "$RESET"
printf '\n'
printf 'Next steps:\n'
printf '  %s1.%s Start a fresh login shell to load both Zsh config files:\n' "$CYAN" "$RESET"
printf '     exec zsh -l\n'
printf '\n'
printf '  %s2.%s Preview the planned changes:\n' "$CYAN" "$RESET"
printf '     dotfiles dry-run\n'
printf '\n'
printf '  %s3.%s Apply when you are ready:\n' "$CYAN" "$RESET"
printf '     dotfiles install\n'
printf '\n'
