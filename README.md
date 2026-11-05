# Dotfiles Bootstrap

A small public bootstrap script for setting up my private [dotfiles](https://github.com/Matt-Cain/dotfiles) repository on a fresh Mac.

## Requirements

- macOS with the Xcode Command Line Tools (`xcode-select --install`), which provide Git
- Access to the private dotfiles repository (the script walks you through `gh` login and SSH)

## Bootstrap

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/Matt-Cain/dotfile-bootstrap/main/bootstrap.sh)
```

The bootstrap:

1. installs Homebrew (asks first) and Dotbot
2. signs in to GitHub and checks SSH access to the private repository
3. clones the repository into `~/dotfiles`
4. saves your Git identity in `~/.gitconfig.local`
5. links the `dotfiles` command into `~/bin` and puts `~/bin` on your Zsh `PATH`

It does not install packages or apply any configuration.

`--yes` (or `DOTFILES_BOOTSTRAP_YES=1`) is for machines without a terminal, such as the test VMs in the dotfiles repo: nothing prompts, the Git identity step is skipped, and when `~/dotfiles` already is a repository the GitHub login and SSH checks are skipped too.

## Next steps

```sh
exec zsh -l       # load ~/bin and Homebrew into your shell
dotfiles setup    # packages, tools, one-time setup (a few minutes)
dotfiles apply    # links, themes, shell cache (seconds)
```
