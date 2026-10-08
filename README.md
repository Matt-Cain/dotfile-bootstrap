# Dotfiles Bootstrap

A small public bootstrap script for setting up my private [dotfiles](https://github.com/Matt-Cain/dotfiles) repository.

## Requirements

* Git
* Access to the private dotfiles repository

## Bootstrap

Run:

```sh
curl -fsSL https://raw.githubusercontent.com/Matt-Cain/dotfiles-bootstrap/main/bootstrap.sh | bash
```

The bootstrap clones the private repository into `~/dotfiles`, sets up the `dotfiles` command in `~/bin`, and ensures `~/bin` is configured in your Zsh `PATH`.

**It does not install or apply the dotfiles configuration.**

## Next steps

Reload your shell configuration:

```sh
source ~/.zshrc
```

Preview the planned changes:

```sh
dotfiles dry-run
```

Apply the configuration when ready:

```sh
dotfiles install
```
