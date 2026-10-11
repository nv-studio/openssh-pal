# Requirements Document

## Project Description (Input)
crud-ssh-keys

Display all existing SSH keys; rename a key (renaming both the private key file and the
public key file); copy a public key to the clipboard; delete a key; and create a new key
through a form page on which the user chooses the name, the type and the remaining
generation parameters.

The design system is being implemented in parallel; this feature builds its UI from those
components at implementation time.

## Introduction

This spec gives open-ssh-gui its key-pair surface: the panel lists the key pairs in the
resolved SSH directory and offers rename, copy, delete and create. It is the first feature
that **writes** to `~/.ssh`, so the conservative-by-construction commitments in `product.md`
stop being theoretical here.

Three decisions shape the requirements and are worth stating up front.

**A key pair is discovered from its public key file.** `~/.ssh` holds private keys, public
keys, `config`, `known_hosts`, `authorized_keys` and whatever else the user put there, and
nothing in a filename distinguishes a private key from an unrelated file. Telling them apart
by *content* would mean reading private key bytes into the app's address space for every
file in the directory, on every refresh. Enumerating `*.pub` instead identifies every pair
exactly, costs one small read per key, and lets the app report type, size, fingerprint and
comment without ever opening a private key. The cost is an edge case named in the boundary
context below.

**Rename moves the whole pair as one unit.** Every OpenSSH tool derives the public key path
from the private key path by appending `.pub` — `ssh-keygen -y`, `ssh-add`, `ssh -i` and
`IdentityFile` all assume it. Renaming one file without the other produces a state the
user's own tooling cannot interpret, so the rename either moves the private key, the public
key and any `<name>-cert.pub` certificate together, or it moves nothing. What rename
deliberately does *not* touch is the comment field inside the public key file: that field is
`user@host` by convention, it is not the filename, and rewriting it would edit a file the
user did not ask to have edited.

**Rename does not update what points at the key.** `IdentityFile` lines in `~/.ssh/config`,
scripts, and anything the user has added to the agent by path all keep referring to the old
name. The app cannot silently fix those — it does not parse the config yet, and it does not
own the user's scripts — so it warns before renaming rather than leaving the user to discover
the breakage at the next connection attempt.

## Boundary Context

- **In scope**: listing key pairs in the resolved SSH directory; presenting each pair's
  type, size, fingerprint and comment; copying a public key to the clipboard; renaming a
  pair, its public key and its certificate sidecar as one unit; deleting a pair after
  explicit confirmation; a create form covering name, type, type-specific parameters,
  comment and passphrase; generating the pair through `ssh-keygen`; the file permissions,
  collision and all-or-nothing rules that mutation implies; in-panel navigation between the
  list and the form; and replacing the design system's temporary showcase.

- **Out of scope**: parsing `~/.ssh/config` or honouring `Include`; creating, editing or
  deleting host entries; updating any reference to a renamed key, in the configuration or
  anywhere else (see the note under Requirement 6); editing the comment inside an existing public key file; changing an
  existing key's passphrase; importing or exporting keys, converting between key formats, or
  producing certificates; adding keys to or removing them from `ssh-agent`; `authorized_keys`
  and anything on a remote host; watching the SSH directory for external changes; moving a
  deleted key to the Trash or any other form of undo; and a user-facing setting for the
  default key type.

- **Adjacent expectations**:
  - `MenuBarExtra` remains the only scene. The list and the create form are both presented
    inside the existing panel at its fixed width; "navigate to a form page" means in-panel
    navigation, not a new window.
  - **This is the spec that removes the design system's showcase.** Requirement 14 of the
    `design-system` spec ships a temporary showcase and records that the next feature spec
    deletes it; Requirement 12 here is that deletion.
  - The design system owns component appearance, and the secret field component
    (`design-system` Requirement 10) ships the redacted control without the reveal policy.
    This feature supplies the policy for the passphrase fields it presents.
  - Key material never leaves the device, and the app stores no credential of its own; both
    are standing product boundaries this feature does not relax.
  - A private key file whose public key file has been deleted will not appear in the list,
    because discovery runs from `*.pub`. Recovering that pair means regenerating the public
    key with `ssh-keygen -y`, which this feature does not offer.

## Requirements

### Requirement 1: Key Pair Discovery and Listing
**Objective:** As a developer, I want to see every key pair in my SSH directory at a glance,
so that I can tell what identities this machine holds without listing the directory myself.

#### Acceptance Criteria
1. When the user opens the menu bar panel, the Key Management feature shall enumerate the resolved SSH directory and present one entry per key pair it finds.
2. The Key Management feature shall identify a key pair from a public key file, and shall treat the file of the same name without the `.pub` extension as that pair's private key.
3. While a public key file has no corresponding private key file, the Key Management feature shall present the entry and shall indicate that the private key is absent.
4. The Key Management feature shall exclude `config`, `known_hosts`, `authorized_keys` and any directory from the presented entries.
5. The Key Management feature shall exclude certificate files ending in `-cert.pub` from the presented entries, and shall associate each with the key pair whose name it extends.
6. If a public key file's contents are not a well-formed OpenSSH public key, then the Key Management feature shall present the entry as unreadable together with its filename, and shall continue presenting the remaining entries.
7. When the resolved SSH directory contains no key pair, the Key Management feature shall present an empty state distinguishing "no keys found" from a directory it could not read.
8. If the resolved SSH directory cannot be read, then the Key Management feature shall present the reason rather than an empty list.
9. When a rename, deletion or creation completes, the Key Management feature shall re-enumerate the directory so that the presented list reflects the change.
10. While the directory is being enumerated, the Key Management feature shall remain responsive to user input.

### Requirement 2: Key Pair Identity and Metadata
**Objective:** As a developer, I want each listed key to show what it actually is, so that I
can tell an old 2048-bit RSA key from a current Ed25519 key without inspecting it.

#### Acceptance Criteria
1. The Key Management feature shall present each key pair's filename, key type, key size, fingerprint and comment.
2. The Key Management feature shall derive every presented attribute from the public key file, and shall not read the private key file to obtain them.
3. The Key Management feature shall present the fingerprint in the same form OpenSSH's own tooling reports, so that it can be compared against that output character for character.
4. While a public key file carries no comment, the Key Management feature shall present the entry without a comment rather than substituting a placeholder value.
5. Where a key pair has an associated certificate file, the Key Management feature shall indicate that the pair carries a certificate.
6. If an attribute cannot be derived from a public key file, then the Key Management feature shall present the entry with that attribute marked unavailable rather than omitting the entry.

### Requirement 3: Copy Public Key to Clipboard
**Objective:** As a developer, I want a key's public half on my clipboard in one click, so
that I can paste it into a hosting provider or an `authorized_keys` file without opening a
terminal.

#### Acceptance Criteria
1. When the user activates the copy control for a key pair, the Key Management feature shall place the contents of that pair's public key file on the system clipboard.
2. The Key Management feature shall place the public key on the clipboard as a single line, byte-for-byte as stored, without a trailing newline.
3. When a copy completes, the Key Management feature shall confirm it to the user.
4. If the public key file cannot be read, then the Key Management feature shall report the reason and shall leave the clipboard unchanged.
5. The Key Management feature shall never place a private key file's contents on the clipboard.
6. The Key Management feature shall not clear or otherwise modify the clipboard after a copy.

### Requirement 4: Rename a Key Pair
**Objective:** As a developer, I want to rename a key and have both of its files follow, so
that a key generated with a default name can be given a meaningful one without leaving the
pair half-renamed.

#### Acceptance Criteria
1. When the user activates the rename control for a key pair, the Key Management feature shall present the pair's current name for editing.
2. When the user confirms a rename, the Key Management feature shall rename the private key file, the public key file and any associated certificate file so that all three continue to share one base name.
3. The Key Management feature shall apply the user-supplied name to the private key file and shall derive the public key file's name by appending `.pub` to it.
4. The Key Management feature shall not modify the contents of any renamed file, including the comment field inside the public key file.
5. When a rename completes, the Key Management feature shall present the pair under its new name with its fingerprint unchanged.
6. If any file in the pair cannot be renamed, then the Key Management feature shall restore every file it has already renamed to its original name and shall report the reason.
7. While a rename is in progress, the Key Management feature shall not accept a second rename, deletion or creation.

### Requirement 5: Name Validation and Collision
**Objective:** As a developer, I want an unusable name rejected before anything is moved, so
that a typo cannot scatter a key pair across my SSH directory or overwrite a file I still
need.

#### Acceptance Criteria
1. If a supplied name is empty or consists only of whitespace, then the Key Management feature shall reject it and shall state why.
2. If a supplied name contains a path separator or resolves outside the SSH directory, then the Key Management feature shall reject it and shall state why.
3. If a supplied name ends in `.pub`, then the Key Management feature shall reject it and shall state that the extension is added to the public key file automatically.
4. If a supplied name matches `config`, `known_hosts` or `authorized_keys`, then the Key Management feature shall reject it and shall state that the name is reserved by OpenSSH.
5. If a supplied name would cause any file the operation writes to replace an existing file in the SSH directory, then the Key Management feature shall reject it and shall name the file that would have been replaced.
6. While a supplied name is rejected, the Key Management feature shall keep the confirming control unavailable.
7. When a supplied name is rejected, the Key Management feature shall leave every file in the SSH directory unchanged.
8. The Key Management feature shall apply the same name rules to a rename and to a creation.

### Requirement 6: Rename Impact on Existing References
**Objective:** As a developer, I want to be told what a rename will break before it happens,
so that I do not discover at the next `ssh` invocation that my config points at a file that
no longer exists.

#### Acceptance Criteria
1. When the user confirms a rename, the Key Management feature shall warn that references to the key's previous path are not updated, and shall require the user to proceed explicitly.
2. The Key Management feature's warning shall name the previous path and the new path.
3. The Key Management feature shall not modify `~/.ssh/config`, any file it includes, or any other file outside the renamed pair.
4. Where SSH configuration reading is available to the app, the Key Management feature shall list the host entries whose identity file names the key being renamed.
5. If the user does not proceed, then the Key Management feature shall leave every file unchanged.

**Note — why a rename warns rather than rewriting `~/.ssh/config`.** Recorded here so the
decision is not re-litigated when the configuration spec arrives.

Rewriting the config would be neither sufficient nor safe:

- **It is not the whole set.** `IdentityFile` is one referent among many. The others include
  `/etc/ssh/ssh_config` (root-owned, outside this app's remit), `ssh -i` in scripts and
  Makefiles, `core.sshCommand` and `GIT_SSH_COMMAND`, `ssh-add` lines in shell startup files
  and launch agents, Ansible's `ansible_ssh_private_key_file`, and editor and client
  configurations. Fixing one of these and reporting success would suppress the check the user
  would otherwise make.
- **A reference cannot always be resolved to a path.** `ssh_config(5)` permits tilde syntax,
  environment variables, and the tokens `%%  %C  %d  %h  %i  %j  %k  %L  %l  %n  %p  %r  %u`
  in an `IdentityFile` argument. `~/.ssh/id_ed25519`, `%d/.ssh/id_ed25519` and
  `$HOME/.ssh/id_ed25519` all name one file, while `%h` and `%r` resolve per connection and
  cannot be matched to a specific key at rename time at all. Multiple `IdentityFile`
  directives are additive rather than overriding, so no one directive can be reasoned about
  alone. A rewriter would therefore have to miss references or guess at them.
- **The cost is asymmetric.** The warning costs one dialog. A faulty rewrite of the file that
  governs access to every machine the user reaches costs that access, as a side effect of an
  operation the user asked for on two key files.

Requirement 6.4 is therefore satisfied vacuously in this iteration and becomes live once
configuration reading exists. **Deliberately deferred to that point:** offering to update the
references the parser can resolve to a concrete path, as an explicit opt-in that lists the
affected entries for review. That is a different obligation from a silent side effect, and it
would never cover the tokenised references, which stay in the warning permanently.

### Requirement 7: Delete a Key Pair
**Objective:** As a developer, I want to remove a key I no longer use, so that my SSH
directory reflects the identities this machine actually needs.

#### Acceptance Criteria
1. When the user activates the delete control for a key pair, the Key Management feature shall request confirmation through the Design System's confirming button style before removing anything.
2. The Key Management feature's confirmation request shall name the key pair and shall state that the removal is permanent and cannot be undone.
3. When the user confirms a deletion, the Key Management feature shall remove the private key file, the public key file and any associated certificate file.
4. When a deletion completes, the Key Management feature shall remove the entry from the presented list.
5. If the user does not confirm, then the Key Management feature shall leave every file unchanged.
6. If any file in the pair cannot be removed, then the Key Management feature shall report the reason and shall name the files that remain.
7. The Key Management feature shall not delete any file the user did not identify through a presented entry.
8. The Key Management feature shall require a separate confirmation for each deletion, and shall not offer a way to suppress the confirmation.
9. The Key Management feature shall supply the confirmation's title and message, naming the key pair and stating that the removal is permanent.

### Requirement 8: Create a Key Pair — Form
**Objective:** As a developer, I want a form that asks for what `ssh-keygen` needs, so that I
can generate a key for a new machine without recalling the flags.

#### Acceptance Criteria
1. When the user activates the create control, the Key Management feature shall present a form for a new key pair in place of the list.
2. The create form shall collect a file name, a key type, a comment and a passphrase.
3. The create form shall offer Ed25519, RSA and ECDSA as key types, and shall select Ed25519 by default.
4. The create form shall present only the parameters that apply to the selected key type, and shall present a key size choice for RSA and a curve choice for ECDSA.
5. When the user changes the key type, the create form shall present the parameters for the newly selected type and shall not retain a parameter that does not apply to it.
6. The create form shall propose a default file name and a default comment that the user can replace.
7. The create form shall require the passphrase to be entered twice, and shall report a mismatch before generation is attempted.
8. Where the user leaves the passphrase empty, the create form shall state that the private key will be stored unencrypted, and shall allow the user to proceed.
9. While any supplied value is invalid, the create form shall keep the generate control unavailable and shall indicate which value is invalid.
10. When the user cancels the form, the Key Management feature shall return to the list and shall discard the entered values without writing any file.

### Requirement 9: Create a Key Pair — Generation
**Objective:** As a developer, I want the app to generate the key through OpenSSH's own
tooling, so that the resulting files are exactly what `ssh-keygen` would have produced from
the terminal.

#### Acceptance Criteria
1. When the user confirms the create form, the Key Management feature shall generate the key pair by invoking `ssh-keygen` with the supplied parameters.
2. The Key Management feature shall not implement any key generation or key serialization of its own.
3. While generation is in progress, the Key Management feature shall present progress and shall keep the generate control unavailable.
4. When generation completes, the Key Management feature shall return to the list and shall present the new key pair with the type, size and comment the user supplied.
5. If `ssh-keygen` cannot be located or cannot be executed, then the Key Management feature shall report that generation is unavailable and shall leave the SSH directory unchanged.
6. If generation fails, then the Key Management feature shall report the reason and shall leave no partially written file in the SSH directory.
7. If the resolved SSH directory does not exist when generation is confirmed, then the Key Management feature shall report that the directory is absent rather than creating it silently.
8. While generation is in progress, the Key Management feature shall complete it even if the user dismisses the panel, and shall present the outcome when the panel is next opened.

### Requirement 10: Private Key Material and Passphrase Handling
**Objective:** As a user, I want my private keys and passphrases to stay out of anything
another process or another person can observe, so that using a GUI is not less safe than
using the terminal.

#### Acceptance Criteria
1. The Key Management feature shall not read the contents of a private key file.
2. The Key Management feature shall not display the contents of a private key file.
3. The Key Management feature shall not transmit any file in the SSH directory off the device.
4. The Key Management feature shall not write a passphrase to any file, log or persistent store.
5. The Key Management feature shall not expose a passphrase in the argument list or the environment of any process it launches, so that the passphrase cannot be observed from a process listing.
6. While the user is entering a passphrase, the create form shall render it redacted, and shall reveal it only when the user explicitly requests it.
7. When generation completes or is abandoned, the Key Management feature shall retain no reference to the entered passphrase.
8. The Key Management feature shall not include a passphrase or a private key path in any user-facing error message.

**Note — the scope of 10.7.** An earlier draft required the passphrase to be discarded "from
memory". That is not something this app can promise. By the time a passphrase reaches the
feature, the text system has already held it, and Swift's copy-on-write string buffers may
hold copies beyond any reach of the app's own code; a GUI process cannot account for what the
window server retains either. The requirement is therefore stated as the obligation the app
can actually discharge and a reviewer can actually check: **no component retains a reference**
once generation finishes or is abandoned. Criteria 10.4, 10.5 and 10.8 carry the rest of the
protection — nothing is written down, nothing reaches a process listing, nothing is printed —
and those are enforceable. Claiming memory scrubbing on top of them would be a promise the
implementation could not keep.

### Requirement 11: File Mutation Safety
**Objective:** As a user, I want the app to leave my SSH directory in a state OpenSSH still
accepts, so that a GUI operation can never cost me access to a machine.

#### Acceptance Criteria
1. The Key Management feature shall restrict every file it creates, renames or deletes to the resolved SSH directory.
2. The Key Management feature shall not replace or delete any existing file that is not part of the key pair the user identified.
3. When a key pair is created, the Key Management feature shall leave the private key file readable and writable only by its owner, and the public key file readable by others, matching what `ssh-keygen` produces at the command line.
4. When a key pair is renamed, the Key Management feature shall preserve each file's existing permissions.
5. If a multi-file operation cannot be completed, then the Key Management feature shall leave the SSH directory in the state it was in before the operation began.
6. The Key Management feature shall perform every file mutation off the main thread, so that the panel remains responsive.
7. The Key Management feature shall not write to the SSH directory except as the direct result of a rename, deletion or creation the user confirmed.
8. Where an override directory was supplied at launch, the Key Management feature shall confine every mutation to that directory and shall never fall back to the user's home directory.

### Requirement 12: Panel Presentation and Navigation
**Objective:** As a developer, I want the key list and the create form to live in the menu bar
panel, so that the app stays the quick visual surface it is meant to be rather than growing a
window.

#### Acceptance Criteria
1. The open-ssh-gui app shall keep `MenuBarExtra` as its only scene.
2. The open-ssh-gui app shall present the key pair list in the menu bar panel in place of the design system's temporary showcase.
3. The open-ssh-gui app shall remove the design system spec's showcase source files, which that spec recorded as temporary.
4. The open-ssh-gui app shall retain the panel's existing Quit control and its keyboard shortcut.
5. When the user navigates between the list and the create form, the open-ssh-gui app shall keep the panel's width unchanged.
6. When the panel opens or the presented content changes, the open-ssh-gui app shall lay it out without triggering AppKit layout recursion.
7. While the key list is longer than the height available, the open-ssh-gui app shall scroll the list within a bounded height rather than growing the panel.
8. When the user navigates from the create form back to the list, the open-ssh-gui app shall present the list without requiring the panel to be reopened.
9. The open-ssh-gui app shall continue to present the resolved SSH directory and its reachability alongside the key list.

### Requirement 13: Design System Adoption and Accessibility
**Objective:** As a developer, I want this feature built from the design system, so that the
first real feature proves the components work and does not start a second vocabulary of
inline styling.

#### Acceptance Criteria
1. The Key Management feature's views shall obtain every control's appearance from the Design System layer.
2. The Key Management feature's views shall not declare a font, spacing, radius or colour value inline.
3. When the Key Management feature requires a value no design token defines, it shall add a token rather than a literal at the call site.
4. The Key Management feature shall present its destructive controls using the Design System's destructive appearance.
5. The Key Management feature shall present its empty state, section headers, list rows and status messages using the Design System's corresponding components.
6. The Key Management feature's views shall contain no file-system access and shall obtain every value they display from an injected model.
7. The Key Management feature shall expose an accessibility label for every control it presents.
8. The Key Management feature shall not convey a key's state by colour alone.
9. The Key Management feature shall render legibly in both light and dark appearance and shall scale with the user's chosen text size.

### Requirement 14: Testability
**Objective:** As a developer, I want every rule in this feature verifiable without a real
SSH directory, so that the test suite can exercise deletion and renaming without risking
anyone's credentials.

#### Acceptance Criteria
1. The Key Management feature's tests shall reach the file system only through an injected port conformer.
2. The Key Management feature's tests shall reach key generation only through an injected conformer, and shall not launch `ssh-keygen`.
3. The Key Management feature's tests shall not reference the user's home directory or any literal SSH directory path.
4. The Key Management feature's tests shall run in the existing test target, which has no host application.
5. The Key Management feature shall express name validation, key pair discovery and public key parsing as pure functions over supplied values, so that each is testable without rendering a view or touching a file.
6. When a test supplies a directory listing, the Key Management feature shall return the key pairs discoverable from it without performing any file-system access of its own.
7. When `xcodebuild … test` is run for a macOS destination, the open-ssh-gui test target shall pass.
