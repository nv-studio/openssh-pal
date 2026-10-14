# Research & Design Decisions — crud-ssh-config-hosts

## Summary
- **Feature**: `crud-ssh-config-hosts`
- **Discovery Scope**: Complex Integration — an extension of the existing layered app that
  introduces the first writer of `~/.ssh/config`. Full discovery for `ssh_config(5)`
  semantics (verified against the OpenSSH sources, not only the man page); light discovery
  for the codebase integration points.
- **Key Findings**:
  - OpenSSH's own tokenizer accepts trailing `# comments`, single *and* double quotes and
    backslash escapes. A lossless line model is mandatory: re-serialising a parsed directive
    would silently drop comments and change quoting.
  - `Include` globs are expanded with glob(3), which never matches a leading-dot name unless
    the pattern itself starts with `.`. Any backup or temporary file the app places beside a
    config file must therefore be a dotfile, or `Include config.d/*` would load it as a
    second copy of every host.
  - A `Host` block's scope ends at the end of the file that declares it — readconf saves and
    restores the active state around every included file. Blocks never span files, so every
    edit is confined to one file.

## Research Log

### `ssh_config(5)` lexical rules
- **Context**: Requirement 9.1 demands byte-for-byte preservation outside the edited block,
  and Requirement 5.2 demands that only changed lines are rewritten. Both depend on knowing
  exactly what a line can contain.
- **Sources Consulted**: local `man ssh_config` (OpenSSH_10.3p1 on the development machine);
  `readconf.c` (`process_config_line_depth`) and `misc.c` (`argv_split`, `strdelim`) from
  `openssh-portable` master.
- **Findings**:
  - Keywords are case-insensitive (`lowercase(keyword)`); arguments are case-sensitive.
  - Keyword and arguments are separated by whitespace or by optional whitespace plus exactly
    one `=`.
  - Lines that are empty, whitespace-only, or whose first token starts with `#` are comments.
  - `argv_split(…, terminate_on_comment = 1)`: a token beginning with `#` ends the line, so
    `User alice # work account` is valid and the comment must survive an edit of the value.
  - Both `"` and `'` open a quoted run; `\"`, `\'`, `\\` and (outside quotes) `\ ` are escapes;
    any other backslash is literal. An unterminated quote is an error ("invalid quotes").
  - Trailing whitespace and a final form feed are stripped before tokenising.
  - An unknown keyword is a fatal "Bad configuration option" for `ssh` unless covered by
    `IgnoreUnknown`. The app must preserve such lines, not repair them.
- **Implications**: the parser keeps every line's raw text and records only the *spans* it
  understands (indent, keyword, separator, argument text, trailing comment). An edit
  replaces the argument span and nothing else. The value formatter quotes with `"` whenever
  a value contains whitespace, `'` or `\`, and escapes `\` as `\\`, so the written line
  tokenises back to exactly the value the user typed.

### `Host` blocks and pattern matching
- **Context**: Requirements 2.10, 3.3, 6.6–6.10 and 7.3 all rely on pattern semantics.
- **Sources Consulted**: `readconf.c` `case oHost`, `match.c` `match_pattern`, `ssh.c`
  (`lowercase(host)`).
- **Findings**:
  - A `Host` line's patterns are whitespace-separated tokens (quoting applies). An empty
    argument is an error.
  - If any negated pattern (`!p`) matches, the block is inactive regardless of other patterns;
    otherwise it is active if any positive pattern matches.
  - `match_pattern` is a case-*sensitive* glob over `*` and `?`, but `ssh` lowercases the host
    name before matching. A pattern containing upper-case letters therefore never matches.
  - A block ends at the next `Host` or `Match` line, or at the end of the file.
- **Implications**: a pure `SSHHostPatternMatcher` reproduces this exactly (lowercase the
  candidate, literal comparison otherwise, negation veto). Duplicate-alias detection compares
  lowercased aliases.

### `Include` semantics
- **Context**: Requirement 1.
- **Sources Consulted**: man page `Include`; `readconf.c` `case oInclude`,
  `read_config_file_depth`, `READCONF_MAX_DEPTH`.
- **Findings**:
  - Multiple paths per directive. Each may contain glob(7) wildcards, `%` tokens, `${ENV}`
    variables and, in user configuration, `~`.
  - A path that is neither absolute nor `~`-prefixed is anchored at `~/.ssh`.
  - `glob(…, GLOB_TILDE)`; results are processed in lexical order. No match is silently
    skipped (debug log only). A matched file that cannot be opened with `ENOENT` is skipped;
    any other open failure is an error.
  - The active state is saved before and restored after each included file, so an included
    file's `Host` blocks never leak into the including file. An `Include` inside an inactive
    block is parsed with `SSHCONF_NEVERMATCH`: its hosts never apply.
  - Depth limit `READCONF_MAX_DEPTH = 16`; exceeding it is `fatal`. There is no separate
    cycle detection — a cycle is caught only by the depth limit.
  - Included files are opened with `SSHCONF_CHECKPERM`: bad owner or group/world-writable
    permissions are fatal.
- **Implications**: the loader walks includes depth-first in file order, enforces depth 16
  and additionally detects cycles by canonical path (reporting earlier and more precisely
  than `ssh`). Tokens other than `%d`, `%u` and `%%` and all `${ENV}` references make an
  `Include` path unresolvable for the app; such a directive is reported as skipped. Each
  entry records the chain of enclosing `Host` patterns it was included under, so
  placement (6.10) can tell an always-applicable block from a conditional one.

### `IdentityFile` resolution
- **Context**: Requirements 2.3–2.7, 3.2, 4.7, 4.8, 11.
- **Sources Consulted**: man page `IdentityFile`, TOKENS, ENVIRONMENT VARIABLES; `readconf.c`
  `add_identity_file`; `ssh.c` `load_public_identity_files` (`tilde_expand_filename` then
  `default_client_percent_dollar_expand`).
- **Findings**:
  - Expansion order is tilde first, then `%` tokens and `${ENV}`.
  - A relative path is **not** anchored anywhere — it is relative to the working directory
    of the `ssh` process.
  - The argument `none` disables identity files.
  - An `IdentityFile` may name a *public* key; `ssh` then uses the matching agent key.
  - Multiple `IdentityFile` directives accumulate; duplicates are ignored.
- **Implications**: the resolver produces a closed outcome — a concrete path, `none`, or
  unresolvable with a reason (connection-time token, environment variable, `~user`, relative
  path). A path matches a key pair if it equals either the private or the public key URL.
  Environment variables are deliberately unresolvable: a GUI app launched by `launchd` does
  not have the user's shell environment, so any value it substituted could differ from what
  `ssh` sees in a terminal.

### Atomic replacement on macOS
- **Context**: Requirements 9.3–9.6.
- **Sources Consulted**: Foundation `FileManager` / `Data.write(options: .atomic)`
  documentation; `rename(2)`, `renamex_np(2)` (`RENAME_EXCL`) and `open(2)` (`O_EXCL`) man
  pages; the existing `FileSystemSSHKeyWriter`.
- **Findings**:
  - `Data.write(options: .atomic)` writes a temporary file and renames it, but the new
    inode gets default permissions (umask, typically `0644`), not the original's.
  - `rename(2)` onto a path that is a symbolic link replaces the **link**, not its target.
    Users who manage `~/.ssh/config` with a dotfiles tool (stow, chezmoi symlink mode)
    would silently lose the link.
  - `renamex_np(…, RENAME_EXCL)` provides an atomic "move into place only if absent", which
    gives both atomicity and no-clobber for a newly created `config`.
- **Implications**: the writer adapter resolves symbolic links, writes a hidden temporary
  file in the *target's* directory, applies the target's mode before the rename, and
  refuses if the resolved target lies outside the SSH directory. Creation uses
  `RENAME_EXCL`, so a `config` that appears concurrently is never overwritten.

### Codebase integration points
- **Context**: light discovery of the existing app.
- **Findings**:
  - `SSHDirectoryReading` (list, probe, read) suffices for loading and glob expansion,
    including multi-level globs walked one directory at a time. No read-port change.
  - `SSHKeyWriting` deliberately has no create or write. Config writing needs both, so it is a
    **new, separate port**; the key port stays create-free.
  - `PanelRoute` (`keyList`, `newKey`) and `PanelView` own navigation; `NewKeyFormModel.cancel()`
    produces a `.cancelled` completion that `PanelView` adopts by returning to the list. A
    tab switch must discard the form **without** producing a completion, or adopting it would
    yank the user back to the Keys tab.
  - `SSHKeyListView` currently refreshes in its own `.task` and owns the "New key" button.
  - `PanelMetrics.height` (564) has about 23 points of slack; a tab bar does not fit inside it.
  - `SSHDirectory` does not record whether it came from an override. "Not the default
    directory" (resolved ≠ home/.ssh) is equivalent for every rule here and needs no resolver
    change.
  - `ChoiceRow` is a native menu picker: macOS renders menu item images as monochrome
    templates, so it cannot carry the orange warning that 4.3 needs.

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| Lossless line model + span edits | Keep every line's raw text; parse only spans; edits replace spans or whole lines | Byte-exact preservation by construction; small, testable editor | Parser must track spans precisely | **Selected** |
| AST + pretty-printer | Parse into a tree, serialise the whole file | Simple editing API | Loses comments, quoting, spacing; violates 9.1 | Rejected |
| Shell out to `ssh -G` | Ask OpenSSH for the effective config | Exact semantics | Per-host only, no file/line attribution, cannot write | Rejected for listing; out of scope |
| Single `SSHConfigManaging` service | One type loads, resolves, edits, writes | Fewer types | Violates interface segregation; untestable writes | Rejected |

## Design Decisions

### Decision: A new `SSHConfigWriting` port with create and replace
- **Context**: the config must be written; `SSHKeyWriting` intentionally cannot create.
- **Alternatives Considered**:
  1. Widen `SSHKeyWriting` with `write`/`create`.
  2. A new narrow port for configuration files only.
- **Selected Approach**: option 2. The port offers `resolvedLocation`, `backUpIfAbsent`,
  `replace(expecting:)` and `create` — each confined to an `SSHDirectory` argument.
- **Rationale**: keeps the key surface structurally unable to create files; a consumer
  holding only the config port cannot move or delete keys.
- **Trade-offs**: one more adapter; compare-then-replace lives in the adapter so the window
  between the check and the rename is as short as possible.
- **Follow-up**: adapter tests against a scratch directory for symlinks, mode preservation,
  `RENAME_EXCL` and concurrent modification.

### Decision: Optimistic concurrency by byte comparison
- **Context**: 9.6 — never overwrite an external edit.
- **Alternatives Considered**: modification date; file-system events; byte comparison.
- **Selected Approach**: the form captures the file's bytes when it opens (the baseline). The
  edit is applied to the baseline, and the adapter replaces the file only if its current bytes
  equal the baseline.
- **Rationale**: modification dates have coarse resolution and editors can preserve them;
  watching for events is out of scope. Config files are small, so comparing them costs little.
- **Trade-offs**: a residual race between the comparison and the rename (microseconds). It
  is accepted and documented.

### Decision: One hidden backup per file, created only if absent
- **Context**: 9.4 — back up before the first modification of a file the app did not create.
- **Selected Approach**: `.<file name>.open-ssh-gui-backup` in the same directory, mode `0600`,
  created with exclusive create. Its existence marks "already backed up". If any loaded
  `Include` pattern would match the backup path, the write is refused rather than the backup
  being placed where `ssh` would read it.
- **Rationale**: the dot prefix keeps glob(3) from matching it; a single pre-app snapshot is
  the most useful restore point and does not accumulate files in `~/.ssh`.
- **Trade-offs**: the app cannot tell a `config` it created in an earlier launch from one it
  did not, so it may back up its own file once. That is harmless and more conservative than
  9.4 requires.

### Decision: Rendering the shared-key warning in the key picker
- **Context**: 4.3 needs the orange warning per key in the picker.
- **Alternatives Considered**: `ChoiceRow` menu with labels; an inline bounded list.
- **Selected Approach**: an inline `BoundedList` of key choices whose rows use
  `StatusRole.warning`; a status line under it names the hosts for the selected key.
- **Rationale**: menu item images render monochrome; the list keeps the same visual language
  as the host list.

### Decision: Tabs as a segmented control, not `TabView`
- **Context**: Requirement 10 inside a fixed-size, content-sized `NSPanel`.
- **Selected Approach**: a design-system `TabBar` built on a segmented `Picker` above the active
  surface, driven by a closed `PanelTab` enum.
- **Rationale**: the same reasoning `PanelRoute` recorded against `NavigationStack` —
  `TabView`'s behaviour inside a content-sized panel is undocumented and is the most likely
  change to bring layout recursion back. A segmented control has a fixed height, exposes the
  selected trait to VoiceOver and shows selection by shape and contrast, not only colour.
- **Trade-offs**: the panel grows by the tab bar's height.

### Decision: Breaking the keys ↔ hosts dependency
- **Context**: hosts need key pairs (association, picker); keys need host references (R11).
- **Selected Approach**: `SSHConfigModel` depends on nothing key-related. `SSHKeyListModel`
  depends on a narrow `HostReferenceLookup` protocol that `SSHConfigModel` conforms to.
  Host presentation receives both models. The construction order in the composition root is
  configuration first, then keys.
- **Rationale**: no reference cycle, and each model remains testable with one fake.

### Decision: Override confinement derived from the resolved directory
- **Context**: 1.10, 9.10.
- **Selected Approach**: confinement applies whenever the resolved directory is not
  `home/.ssh`. Relative `Include` paths are anchored at the resolved directory (identical to
  `ssh` in the default case), and `~` always expands to the real home, which is then outside
  an override directory and therefore skipped.
- **Rationale**: needs no change to `SSHDirectoryResolver` and cannot fall back to the real
  directory.

## Risks & Mitigations
- **Swift `Character` merges `\r\n` into one grapheme** — line splitting on `Character`
  would hide CRLF endings. Mitigation: split on the raw bytes (or Unicode scalars), and test
  CRLF round trips.
- **A tokenizer that differs from OpenSSH's** would misread a value and rewrite the wrong
  span. Mitigation: port `argv_split` semantics exactly and test them against a table of
  OpenSSH-derived cases (quotes, escapes, trailing comments, `=` separators).
- **Placement into a file with unusual structure** (blocks only in includes, `Match` first).
  Mitigation: rules 6.6–6.9 are pure and covered case by case; 6.10 warns rather than guesses.
- **The panel height grows** — check on a 13-inch display at the largest text size.
  Mitigation: re-measure as `PanelMetrics` documents and keep the bottom margin.
- **Non-UTF-8 config files** cannot be edited losslessly as text. Mitigation: present them
  read-only with a reason.

## References
- `ssh_config(5)` — OpenSSH 10.3p1 manual page (local `man ssh_config`).
- [openssh-portable `readconf.c`](https://github.com/openssh/openssh-portable/blob/master/readconf.c) — Host, Include, IdentityFile, depth limit.
- [openssh-portable `misc.c`](https://github.com/openssh/openssh-portable/blob/master/misc.c) — `argv_split` quoting, escapes and trailing comments.
- [openssh-portable `match.c`](https://github.com/openssh/openssh-portable/blob/master/match.c) — `match_pattern`.
- [openssh-portable `ssh.c`](https://github.com/openssh/openssh-portable/blob/master/ssh.c) — host lowercasing; identity file expansion order.
- `rename(2)`, `renamex_np(2)`, `glob(3)` — macOS manual pages.
