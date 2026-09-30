# Product Overview

**open-ssh-gui** is a macOS menu bar app for managing OpenSSH host configurations and key
pairs. It serves developers and operators who already use `ssh` from the terminal and want a
quick visual surface onto the files they maintain by hand.

It is an **addon to** the normal OpenSSH tooling, never a replacement.

## Core Capabilities

- View, create, edit and delete SSH host configurations in `~/.ssh/config` and the files it
  `Include`s.
- View, create and delete private/public key pairs (`~/.ssh/id_*`, `~/.ssh/*.pub`).
- Report which SSH directory the app is working with, and why it cannot be read when it
  cannot.
- Live in the menu bar as the primary UI surface, with no Dock presence.

## Target Use Cases

- Checking or correcting a host entry without opening an editor.
- Generating a key pair for a new machine without recalling `ssh-keygen` flags.
- Confirming at a glance that the app is pointed at the expected directory.

## Value Proposition

The app's value is that it **defers to OpenSSH** rather than owning the user's configuration.
Three commitments follow from that, and they shape every feature:

**The files stay hand-editable.** Anything the app writes must remain valid, idiomatic
OpenSSH configuration that the user can open in an editor afterwards. The `ssh`, `ssh-keygen`
and `sshd_config` man pages are the source of truth for formats and semantics — not the app's
own model.

**What the app does not understand, it preserves.** Round-tripping a config keeps unknown
keywords, comments, blank lines, ordering and indentation intact. An edit to one host block
never rewrites the whole file. A user should be unable to tell, from the file, that a GUI
touched it.

**These are live credentials.** `~/.ssh` is how the user reaches real machines; damaging it
costs them access. This is why the app is conservative by construction rather than by
convention — see `tech.md` for the read-only port and the test-isolation controls that
implement it. Deleting a key is irreversible and always requires explicit confirmation.

## Product Boundaries

Deliberately out of scope: acting as an SSH *client* (the app never opens connections),
managing `sshd` or server-side configuration, storing credentials anywhere of its own, and
syncing or backing up `~/.ssh` off the machine. No `~/.ssh` content ever leaves the device.

---
_Focus on patterns and purpose, not exhaustive feature lists_
