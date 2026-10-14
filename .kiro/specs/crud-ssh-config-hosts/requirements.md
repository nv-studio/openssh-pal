# Requirements Document

## Project Description (Input)
crud-ssh-config-hosts

1. The app should read all hosts at app startup from the SSH config location, taking its
   include (`Include`) statements into consideration.
2. A user should be able to see a list of the hosts with their associated SSH key.
3. A user should be warned, with an orange icon, about using the same SSH key with two
   different hosts.
4. A user should be able to edit a host.
5. A user should be able to create a new host: when doing so they are presented with a list
   of all the available keys, and the ones already assigned to another host are again
   presented with a warning.
6. The app should present a top navigation tab bar, with a page for keys (the current one,
   and the default), a "Hosts" tab, and a "New Key" tab for the new key form.

## Introduction

This spec gives open-ssh-gui its host surface. The app reads `~/.ssh/config` and every file it
`Include`s, lists the `Host` entries it finds together with the key each one uses, flags a key
shared between hosts, and lets the user edit an entry, create one and delete one. It also
replaces the panel's two-route navigation with a tab bar: **Keys**, **Hosts** and **New Key**.

It is the first feature that **writes to `~/.ssh/config`**. A damaged key costs access to the
machines that one key opens; a damaged config can cost access to all of them. The
preservation commitments in `product.md` therefore stop being aspirations here and become
acceptance criteria.

Four decisions shape the requirements.

**A host entry is a `Host` block, not a computed effective configuration.** `ssh_config(5)`
assigns each parameter the *first* value obtained across every matching block in file order,
so what `ssh` actually uses for a host can depend on a `Host *` block, a wildcard block, a
`Match` block or an include several files away. Recomputing that is `ssh -G`'s job, and a
partial reimplementation would be wrong in exactly the cases where the user most needs it to
be right. The app therefore presents and edits what each block *declares*, attributed to the
file and line it is declared on, and says so.

**A key is "assigned to a host" when an `IdentityFile` in that host's block resolves to a
listed key pair.** `IdentityFile` accepts tilde syntax, environment variables and `%` tokens.
Some of these resolve without a connection (`~`, `%d`, `%u`, `%%`) and some cannot (`%h`,
`%r`, `%n`, `%p` and others resolve per connection). A reference the app cannot resolve to a
concrete path is presented exactly as written and is never guessed at — the same reasoning
`crud-ssh-keys` recorded under its Requirement 6.

**The shared-key warning considers concrete hosts only.** A block whose every pattern contains
a wildcard (`*`, `?`) or is negated (`!`) describes a *policy* — "use this key everywhere" —
rather than a host. Counting it would flag every host that also names the same key, which
turns the warning into noise. These blocks are still listed, and still show their key; they
just do not count toward a duplicate.

**An edit rewrites one block's lines and nothing else.** A user must not be able to tell from
the file that a GUI touched it. Unknown keywords, comments, blank lines, indentation, ordering
and every other block survive byte for byte, and the app refuses to write over a file that
changed on disk after it was read.

## Boundary Context

- **In scope**: reading `~/.ssh/config` at launch and following its `Include` directives;
  listing every `Host` block with its patterns, host name, user, port and identity files;
  resolving identity files to the key pairs `crud-ssh-keys` discovers; the shared-key warning
  in the host list and in the key picker; an edit form and a create form for host entries;
  deleting a host entry after confirmation; the atomic-write, backup, permission,
  preservation and concurrent-modification rules that writing the config implies; a top tab
  bar replacing the panel's current two-route navigation; and naming the hosts that use a key
  when that key is renamed or deleted.

- **Out of scope**: computing a host's effective configuration (`ssh -G`); presenting or
  editing `Match` blocks, other than preserving them; editing directives beyond `Host`,
  `HostName`, `User`, `Port` and `IdentityFile`, other than preserving them; adding,
  removing or editing `Include` directives; writing to `/etc/ssh/ssh_config` or any file
  outside the resolved SSH directory; automatically rewriting `IdentityFile` references when
  a key is renamed or deleted (deferred by `crud-ssh-keys` Requirement 6 and still
  deferred); adding `IdentitiesOnly` or any other directive the user did not ask for; opening
  connections or testing a host; watching the config for external changes while the panel
  is idle; reordering host blocks; and any form of undo beyond the backup taken before the
  first modification.

- **Adjacent expectations**:
  - `MenuBarExtra` remains the only scene. The tab bar, the host list and the host forms are
    all presented inside the existing panel at its fixed width and height.
  - `crud-ssh-keys` owns key discovery, key metadata and the New Key form. This feature
    consumes the discovered key pairs, and moves the existing New Key form behind a tab
    without changing its fields or its rules.
  - `crud-ssh-keys` Requirement 6.4 ("where SSH configuration reading is available, list the
    host entries whose identity file names the key being renamed") is satisfied vacuously
    today. This feature makes configuration reading available, so that criterion becomes
    live; Requirement 11 here supplies what it needs.
  - The design system owns the warning colour. Its `warning` role is the amber/orange the
    request asks for, and it always pairs a symbol with the colour, which is what lets
    Requirement 3 avoid conveying the warning by colour alone.

## Requirements

### Requirement 1: Configuration Loading and Include Resolution
**Objective:** As a developer, I want the app to read my SSH configuration, including every
file it pulls in, as soon as it starts, so that the hosts are ready when I first open the
panel and none are missing because they live in an included file.

#### Acceptance Criteria
1. When the open-ssh-gui app launches and the SSH directory has resolved, the Host Configuration feature shall read the `config` file in the resolved SSH directory.
2. When the configuration being read contains an `Include` directive, the Host Configuration feature shall read every file the directive names, at the position in file order where the directive appears.
3. The Host Configuration feature shall resolve a relative `Include` path against the resolved SSH directory, and shall expand tilde syntax and glob patterns in an `Include` path as `ssh_config(5)` specifies.
4. When an `Include` glob matches several files, the Host Configuration feature shall read them in lexical order.
5. When an `Include` directive appears inside a `Host` block, the Host Configuration feature shall read the files it names and shall present the hosts they declare.
6. If a file named by an `Include` directive does not exist, then the Host Configuration feature shall skip it without reporting an error, as `ssh` does.
7. If `Include` directives form a cycle or exceed the nesting depth `ssh` accepts, then the Host Configuration feature shall stop following them, shall report the file at which it stopped, and shall present the hosts read up to that point.
8. If the `config` file does not exist, then the Host Configuration feature shall present an empty host list stating that no configuration file exists, distinct from a file it could not read.
9. If the `config` file or an included file exists but cannot be read, then the Host Configuration feature shall report the reason and the file, and shall present the hosts from every file it could read.
10. Where an override SSH directory was supplied at launch, the Host Configuration feature shall not read any included file outside that directory, and shall report each such file as skipped.
11. When the user opens the menu bar panel, the Host Configuration feature shall re-read the configuration, so that an edit made in a text editor while the app was running is presented.
12. When a host is created, edited or deleted, the Host Configuration feature shall re-read the configuration, so that the presented list reflects the change.
13. While the configuration is being read, the open-ssh-gui app shall remain responsive to user input.

### Requirement 2: Host List
**Objective:** As a developer, I want a list of my configured hosts with the key each one uses,
so that I can see where every identity is used without opening the config file.

#### Acceptance Criteria
1. When the user selects the Hosts tab, the Host Configuration feature shall present one entry per `Host` block found across the configuration and its included files, in file order.
2. The Host Configuration feature shall present each entry's patterns, and its `HostName`, `User` and `Port` values where the block declares them.
3. The Host Configuration feature shall present, for each entry, the key associated with every `IdentityFile` directive the block declares.
4. When an `IdentityFile` value resolves to a key pair listed in the Keys tab, the Host Configuration feature shall present that key pair's name.
5. If an `IdentityFile` value resolves to a path that is not a listed key pair, then the Host Configuration feature shall present the value as written and shall indicate that it does not match a listed key.
6. If an `IdentityFile` value contains a token or environment variable that cannot be resolved without a connection, then the Host Configuration feature shall present the value as written and shall indicate that it could not be resolved, without guessing at a key.
7. While a host block declares no `IdentityFile`, the Host Configuration feature shall indicate that the host uses OpenSSH's default identities rather than presenting it as having no key.
8. The Host Configuration feature shall present only what each block declares, and shall not present values inherited from other blocks.
9. Where an entry was declared in a file other than `config`, the Host Configuration feature shall indicate the file that declares it.
10. Where every pattern of an entry contains a wildcard or is negated, the Host Configuration feature shall present the entry as a pattern entry, distinguishable from a concrete host.
11. The Host Configuration feature shall not present `Match` blocks as host entries.
12. If a line in the configuration cannot be parsed, then the Host Configuration feature shall report the file and line, and shall continue presenting every entry it could parse.
13. While the host list is longer than the height available, the open-ssh-gui app shall scroll the list within a bounded height rather than growing the panel.

### Requirement 3: Shared Key Warning
**Objective:** As a developer, I want to be warned when one key is used for several hosts, so
that I notice key reuse I may not have intended and can decide whether to separate them.

#### Acceptance Criteria
1. When the same key pair is associated with two or more concrete host entries, the Host Configuration feature shall mark each of those entries with a warning icon in the Design System's warning appearance.
2. The Host Configuration feature shall treat two `IdentityFile` values as the same key when they resolve to the same key pair, regardless of how each value is spelled.
3. The Host Configuration feature shall not count a pattern entry toward a shared-key warning.
4. When the user inspects a shared-key warning, the Host Configuration feature shall name the other hosts that use the same key.
5. The Host Configuration feature shall expose the shared-key warning to accessibility technologies with a label stating that the key is shared and naming the other hosts.
6. The Host Configuration feature shall convey the shared-key warning with an icon as well as a colour, and shall not convey it by colour alone.
7. The Host Configuration feature shall present the shared-key warning as advisory, and shall not block saving, creating or connecting because of it.
8. When the last other host using a key stops using it, the Host Configuration feature shall remove the warning from the remaining entry.

### Requirement 4: Key Selection for a Host
**Objective:** As a developer, I want to choose a host's key from the keys I already have,
with reused keys flagged, so that I assign identities deliberately rather than by typing
paths.

#### Acceptance Criteria
1. When the user is choosing a key for a host, the Host Configuration feature shall present every key pair listed in the Keys tab.
2. The Host Configuration feature shall offer a choice of no key, which leaves the host using OpenSSH's default identities.
3. Where a key pair is already associated with a concrete host entry other than the one being edited or created, the Host Configuration feature shall mark it with the same warning icon as the host list and shall name the hosts that use it.
4. The Host Configuration feature shall allow the user to choose a key pair that is already in use, and shall not require a further confirmation to do so.
5. If a listed key pair's private key file is absent, then the Host Configuration feature shall present it as unavailable and shall not allow it to be chosen.
6. When the Keys tab presents no key pairs, the Host Configuration feature shall state that no keys exist and shall offer only the no-key choice.
7. When the user chooses a key pair, the Host Configuration feature shall write an `IdentityFile` value that refers to that key pair's private key file.
8. Where the resolved SSH directory is the user's default SSH directory, the Host Configuration feature shall write the `IdentityFile` value in tilde form, and shall otherwise write the absolute path of the private key file.

### Requirement 5: Edit a Host
**Objective:** As a developer, I want to change a host's address, user, port or key from the
panel, so that I can correct an entry without opening an editor.

#### Acceptance Criteria
1. When the user activates the edit control for a host entry, the Host Configuration feature shall present a form populated with that block's patterns, `HostName`, `User`, `Port` and key.
2. When the user saves the form, the Host Configuration feature shall rewrite only the lines that declare a changed value within that block.
3. When the user clears an optional value and saves, the Host Configuration feature shall remove that directive from the block.
4. When the user supplies a value the block did not declare and saves, the Host Configuration feature shall add the directive to that block.
5. The Host Configuration feature shall preserve every directive in the block that the form does not present, together with its value, position and comments.
6. Where a block declares more than one `IdentityFile`, or one that cannot be resolved to a listed key pair, the Host Configuration feature shall present each value and shall leave them unchanged unless the user explicitly replaces them.
7. The Host Configuration feature shall write the edit to the file that declares the block, including when that file is an included file.
8. If the block is declared in a file outside the resolved SSH directory, then the Host Configuration feature shall present the entry as read-only and shall state why.
9. When the user cancels the form, the Host Configuration feature shall return to the host list and shall discard the entered values without writing any file.
10. When an edit completes, the Host Configuration feature shall return to the host list and shall present the entry with its new values.

### Requirement 6: Create a Host
**Objective:** As a developer, I want to add a host through a form, so that I can configure a
new machine without remembering the config syntax.

#### Acceptance Criteria
1. When the user activates the create control in the Hosts tab, the Host Configuration feature shall present a form for a new host entry in place of the host list.
2. The create form shall collect a host alias, a host name, a user, a port and a key.
3. The create form shall require a host alias, and shall treat the host name, user, port and key as optional.
4. The create form shall present the key choice defined in Requirement 4.
5. When the user confirms the create form, the Host Configuration feature shall add a new `Host` block to the `config` file in the resolved SSH directory, containing only the directives the user supplied.
6. The Host Configuration feature shall place the new block immediately before the first `Host` block in `config` with a pattern that matches the new alias, as `ssh_config(5)` evaluates patterns including wildcards and negation, so that an earlier matching block does not pre-empt the new host's values under first-obtained-value-wins.
7. Where no `Host` block in `config` has a pattern that matches the new alias, the Host Configuration feature shall append the new block at the end of `config`.
8. The Host Configuration feature shall never place the new block above the first `Host` or `Match` line in `config`, so that global directives and `Include` lines preceding it continue to apply to every host and are not absorbed into the new block.
9. The Host Configuration feature shall disregard `Match` blocks when choosing where to place the new block, and shall leave them unchanged.
10. If a block that matches the new alias would still precede the new block, because it lies above the chosen position in an included file or in the global section, then the Host Configuration feature shall warn that the directives it sets take precedence and shall name its file, and shall allow the user to proceed.
11. The Host Configuration feature shall write the new block in the indentation style the file already uses, and shall separate it from adjacent blocks with a blank line.
12. If the `config` file does not exist, then the Host Configuration feature shall create it containing the new block, readable and writable only by its owner.
13. If the resolved SSH directory does not exist, then the Host Configuration feature shall report that the directory is absent rather than creating it.
14. When the user cancels the form, the Host Configuration feature shall return to the host list and shall discard the entered values without writing any file.
15. When a creation completes, the Host Configuration feature shall return to the host list and shall present the new entry.

### Requirement 7: Host Value Validation
**Objective:** As a developer, I want an unusable value rejected before anything is written,
so that a typo cannot produce a config `ssh` refuses to read.

#### Acceptance Criteria
1. If a supplied host alias is empty or consists only of whitespace, then the Host Configuration feature shall reject it and shall state why.
2. If a supplied host alias on the create form contains whitespace, a wildcard character or a negation, then the Host Configuration feature shall reject it and shall state that the create form adds a single concrete host.
3. If a supplied host alias matches a pattern of an existing concrete host entry, then the Host Configuration feature shall reject it and shall name the entry it duplicates.
4. If a supplied port is not an integer from 1 to 65535, then the Host Configuration feature shall reject it and shall state the valid range.
5. If any supplied value contains a line break, a `#` or a double quote, then the Host Configuration feature shall reject it and shall name the character.
6. If a supplied host name or user contains whitespace, then the Host Configuration feature shall reject it and shall state why.
7. While any supplied value is rejected, the Host Configuration feature shall keep the confirming control unavailable and shall indicate which value is rejected.
8. When a supplied value is rejected, the Host Configuration feature shall leave every file unchanged.
9. The Host Configuration feature shall apply the same value rules to an edit and to a creation, except that an edit may keep patterns the block already declares.

### Requirement 8: Delete a Host
**Objective:** As a developer, I want to remove a host entry I no longer need, so that my
configuration reflects the machines I actually use.

#### Acceptance Criteria
1. When the user activates the delete control for a host entry, the Host Configuration feature shall request confirmation through the Design System's confirming button style before removing anything.
2. The Host Configuration feature's confirmation request shall name the host entry and the file that declares it.
3. When the user confirms a deletion, the Host Configuration feature shall remove the block's `Host` line, every line belonging to that block, and the comment lines directly above the `Host` line that are attached to it.
4. The Host Configuration feature shall not delete the key pair associated with a deleted host entry.
5. If the user does not confirm, then the Host Configuration feature shall leave every file unchanged.
6. If the block is declared in a file outside the resolved SSH directory, then the Host Configuration feature shall not offer deletion and shall state why.
7. When a deletion completes, the Host Configuration feature shall remove the entry from the presented list.

### Requirement 9: Configuration Write Safety
**Objective:** As a user, I want every change to my config to leave it valid and recognisably
mine, so that a GUI edit can never cost me access to a machine or my own formatting.

#### Acceptance Criteria
1. The Host Configuration feature shall preserve, byte for byte, every line of every file it writes that lies outside the block being edited, created or deleted.
2. The Host Configuration feature shall preserve the file's line ending convention and the presence or absence of a final newline.
3. When the Host Configuration feature writes a file, it shall write the complete new contents to a temporary file in the same directory and then replace the original, so that an interrupted write cannot leave a truncated file.
4. Before the first modification of a file the open-ssh-gui app did not create, the Host Configuration feature shall create a backup copy of it in the same directory, readable and writable only by its owner.
5. When the Host Configuration feature replaces an existing file, it shall preserve that file's permissions.
6. If a file has changed on disk since the Host Configuration feature last read it, then the Host Configuration feature shall not write it, shall report that the file changed, and shall re-read the configuration.
7. If a write fails, then the Host Configuration feature shall report the reason and shall leave the original file unchanged.
8. The Host Configuration feature shall write only to the file that declares the affected block, or to `config` for a new block, and shall not modify any other file.
9. The Host Configuration feature shall restrict every write to the resolved SSH directory.
10. Where an override SSH directory was supplied at launch, the Host Configuration feature shall confine every write to that directory and shall never fall back to the user's home directory.
11. The Host Configuration feature shall perform every file read and write off the main thread.
12. The Host Configuration feature shall not write to the SSH directory except as the direct result of an edit, creation or deletion the user confirmed.
13. While a write is in progress, the Host Configuration feature shall not accept a second edit, creation or deletion.
14. The Host Configuration feature shall not transmit any configuration content off the device.

### Requirement 10: Tabbed Panel Navigation
**Objective:** As a developer, I want the panel organised into tabs, so that keys, hosts and
key creation are each one click away.

#### Acceptance Criteria
1. The open-ssh-gui app shall present a tab bar at the top of the menu bar panel with the tabs Keys, Hosts and New Key, in that order.
2. When the panel is first opened after launch, the open-ssh-gui app shall select the Keys tab.
3. When the user selects a tab, the open-ssh-gui app shall present that tab's surface in place of the previous one.
4. The Keys tab shall present the existing key pair list.
5. The New Key tab shall present the existing create-key form, with its fields and rules unchanged.
6. The open-ssh-gui app shall make the New Key tab the entry point to the create-key form, in place of the key list's create control.
7. When a key generation completes, the open-ssh-gui app shall select the Keys tab and shall present the new key pair.
8. While a key generation is in progress, the open-ssh-gui app shall complete it if the user selects another tab, and shall present the outcome when the user returns.
9. When the user selects another tab while a host or key form holds unsaved values, the open-ssh-gui app shall discard them without writing any file, and shall retain no reference to an entered passphrase.
10. The Hosts tab shall present the host create and edit forms within the tab, in place of the host list, and shall keep the tab bar visible.
11. When the user switches tabs, the open-ssh-gui app shall keep the panel's width and height unchanged.
12. When the panel opens or the selected tab changes, the open-ssh-gui app shall lay it out without triggering AppKit layout recursion.
13. The open-ssh-gui app shall keep `MenuBarExtra` as its only scene, and shall retain the panel's Quit control and its keyboard shortcut on every tab.
14. The open-ssh-gui app shall indicate which tab is selected by more than colour alone, and shall expose each tab to accessibility technologies with its name and selected state.

### Requirement 11: Key Management Cross-References
**Objective:** As a developer, I want to know which hosts depend on a key before I rename or
delete it, so that I do not break a host without realising it.

#### Acceptance Criteria
1. When the user confirms a key rename, the Key Management feature shall list the host entries with an `IdentityFile` that resolves to the key being renamed, satisfying `crud-ssh-keys` Requirement 6.4.
2. When the user requests a key deletion, the Key Management feature's confirmation shall list the host entries with an `IdentityFile` that resolves to the key being deleted.
3. If the configuration could not be read, then the Key Management feature shall state that host references could not be checked rather than presenting an empty list.
4. Where an `IdentityFile` value could not be resolved, the Key Management feature shall state that unresolved references exist and might name the key.
5. The Key Management feature shall not modify any configuration file as part of a rename or deletion.

### Requirement 12: Design System Adoption and Accessibility
**Objective:** As a developer, I want the host surface built from the design system, so that
it looks and behaves like the key surface it sits beside.

#### Acceptance Criteria
1. The Host Configuration feature's views shall obtain every control's appearance from the Design System layer.
2. The Host Configuration feature's views shall not declare a font, spacing, radius or colour value inline.
3. When the Host Configuration feature requires a value no design token defines, it shall add a token rather than a literal at the call site.
4. The Host Configuration feature shall present its destructive controls using the Design System's destructive appearance.
5. The Host Configuration feature shall present its empty state, list rows, form fields and status messages using the Design System's corresponding components.
6. The Host Configuration feature's views shall contain no file-system access and shall obtain every value they display from an injected model.
7. The Host Configuration feature shall expose an accessibility label for every control it presents.
8. The Host Configuration feature shall render legibly in both light and dark appearance and shall scale with the user's chosen text size.

### Requirement 13: Testability
**Objective:** As a developer, I want every rule in this feature verifiable without a real SSH
directory, so that the tests can exercise rewriting a config without risking anyone's access.

#### Acceptance Criteria
1. The Host Configuration feature's tests shall reach the file system only through an injected port conformer.
2. The Host Configuration feature's tests shall not reference the user's home directory or any literal SSH directory path.
3. The Host Configuration feature's tests shall run in the existing test target, which has no host application.
4. The Host Configuration feature shall express configuration parsing, `Include` resolution, `IdentityFile` resolution, shared-key detection, value validation and block rewriting as pure functions over supplied values, so that each is testable without rendering a view or touching a file.
5. When a test parses a configuration and writes it back without an edit, the Host Configuration feature shall produce output identical to the input.
6. When a test applies an edit to one block, the Host Configuration feature shall produce output in which every line outside that block is identical to the input.
7. When `xcodebuild … test` is run for a macOS destination, the open-ssh-gui test target shall pass.
