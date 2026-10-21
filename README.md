# OpenSSH Pal

OpenSSH Pal is a macOS menu bar app for managing your OpenSSH hosts and keys. It's for
developers and operators who already use `ssh` in the terminal and want a quick visual view
of the files they normally edit by hand.

It works alongside the standard OpenSSH tools and doesn't replace them. OpenSSH Pal reads and
writes your real `~/.ssh` files directly, and everything it writes stays valid OpenSSH
configuration that you can still edit by hand. Comments, unknown keywords, ordering and
indentation it doesn't understand are left as they are. The app never opens connections, and
none of your `~/.ssh` content ever leaves your Mac.

## Features

- **Host management:** view, create, edit and delete host entries in `~/.ssh/config`,
  including hosts defined in files pulled in with `Include`.
- **Key management:** view, create and delete private/public key pairs in `~/.ssh`. New keys
  are generated with `ssh-keygen` and get the correct file permissions. Deleting a key always
  asks you to confirm first.

## Installation

OpenSSH Pal is distributed through Homebrew as a signed and notarized app.

```sh
brew install --cask nv-studio/tap/openssh-pal
```

This adds the `nv-studio/tap` tap and installs the app. After that, launch **OpenSSH Pal**
from Spotlight or `/Applications`. It shows up as an icon in the menu bar and has no Dock
icon. To quit, use the Quit control in the menu bar panel.

### Updating

```sh
brew upgrade --cask openssh-pal
```

### Uninstalling

```sh
brew uninstall --cask openssh-pal
```

Uninstalling removes only the app. Your `~/.ssh` files are left untouched.

### Requirements

- macOS 26 or later
- [Homebrew](https://brew.sh)

## License

OpenSSH Pal is released under the [MIT License](LICENSE).
