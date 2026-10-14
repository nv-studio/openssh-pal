# Implementation Plan

- [x] 1. Foundation: configuration vocabulary, write port and test support
- [x] 1.1 Define the lossless configuration and host-entry value types
  - Represent one configuration file as its original bytes, its lines in order (raw text plus each line's own terminator), its dominant line terminator, its final-newline state, its inclusion chain and its writability
  - Classify each line as blank, comment, directive (case-insensitive keyword, unescaped arguments and the source spans of indentation, keyword and argument run) or malformed with a reason
  - Represent a host entry with a load-scoped identity (file plus block ordinal), its line range, patterns (text, negation, wildcard), the first declared host name, user and port, every identity file in order, the keywords it repeats, and a pattern-entry projection that is true when every pattern is wildcarded or negated
  - Represent an identity reference as its raw text plus a resolution of path, disabled or unresolvable-with-reason, and the resolution context (home directory, resolved SSH directory, user name, whether the directory is the default one)
  - Represent load issues (unparseable line, unreadable file, skipped include with reason, depth exceeded, cycle), the host draft, the key choice (unchanged, none, a named pair) and per-field draft errors, all as closed types with no invalid combination expressible
  - Unit tests pass for the pattern-entry projection, the default-directory projection and value equality of every type
  - _Requirements: 2.2, 2.8, 2.10, 9.1, 9.2, 13.4_

- [x] 1.2 Declare the configuration write port and its in-memory test double
  - Declare a separate writing port for configuration files that offers resolving a file's real location, backing a file up if no backup exists, replacing a file only if its bytes still equal an expected baseline, and creating a file that must not already exist, each confined to the resolved SSH directory and failing with a typed error that names the file
  - Leave the existing read port and key write port unchanged
  - Provide an in-memory, internally locked conformer for tests that holds file contents, records every call, and can simulate an external change or a write failure
  - Observable when the port and the double compile and a test confirms the double refuses a replace whose expected bytes differ
  - _Requirements: 9.3, 9.6, 9.7, 9.9, 13.1_

- [x] 1.3 Build the shared configuration fixture corpus
  - Collect configuration texts covering CRLF and LF endings, a missing final newline, a byte-order mark, tabs, `=` separators, both quote styles, escapes, trailing comments, unknown keywords, repeated keywords, `Match` blocks, a global `Include`, an `Include` inside a `Host` block and non-ASCII values
  - Make the corpus reusable by the tokenizer, parser, editor and round-trip suites, with no reference to a home directory or a literal SSH directory path
  - Observable when the corpus is available to tests and a test enumerates every fixture
  - _Requirements: 13.2, 13.5, 13.6_

- [x] 2. Reading the configuration
- [x] 2.1 Tokenize a configuration line exactly as OpenSSH reads it
  - Treat empty, whitespace-only and `#`-first lines as comments, and strip trailing whitespace and a final form feed before reading
  - End the keyword at whitespace or `=`, accepting whitespace or optional whitespace plus one `=` as the separator
  - Split arguments with OpenSSH's quoting and escape rules, ending the line at a token that starts with `#`, and classify an unterminated quote as malformed while keeping the raw text
  - Return the unescaped arguments together with the spans needed to replace only the argument run later
  - Table-driven tests derived from OpenSSH behaviour pass for every separator, quote, escape, comment and keyword-case case
  - _Requirements: 2.12, 9.1, 13.4_

- [x] 2.2 Parse a file losslessly into lines, blocks, host entries and include directives
  - Split lines on the line-feed byte and record a preceding carriage return as part of the terminator, never splitting on characters
  - Derive `Host` and `Match` block ranges, produce one host entry per `Host` block in file order and never one for a `Match` block
  - Record each block's own declared values only, the keywords it repeats, every malformed line number, and every `Include` with its line and enclosing condition
  - Load a file that is not valid UTF-8 as read-only, listing its entries from a lossy decode
  - Round-trip tests pass: for every fixture, concatenating the parsed lines reproduces the input bytes exactly
  - _Requirements: 2.1, 2.2, 2.8, 2.11, 2.12, 9.1, 9.2, 13.4, 13.5_

- [x] 2.3 (P) Expand and anchor include paths with glob matching
  - Anchor a relative path to the resolved SSH directory, and expand `~/`, `%d`, `%u` and `%%`
  - Report an argument containing an environment variable, another user's home or any other token as unresolvable rather than following it
  - Match wildcard segments one directory level at a time with glob semantics, where a leading dot only matches a pattern segment that starts with a dot, and sort matches lexically
  - Report a resolved path outside an override directory as skipped
  - Unit tests pass for anchoring, every expansion, leading-dot exclusion, lexical ordering and override confinement
  - _Boundary: IncludePathExpander, GlobPattern_
  - _Requirements: 1.3, 1.4, 1.10, 13.4_

- [x] 2.4 Load the configuration and follow its includes through the read port
  - Read `config` in the resolved directory, then follow each `Include` depth-first at the position it appears, including an `Include` inside a `Host` block, so entries come out in flattened load order
  - Skip a missing included file silently, record any other read failure with its file and keep loading
  - Stop a branch at nesting depth 16 or at a file already on the current chain, recording the file, while keeping everything loaded so far
  - Distinguish a missing `config` from an unreadable one, mark files outside the resolved directory read-only, and collect every expanded include path for backup safety
  - Perform all reading through the injected read port so the load runs off the main actor
  - Integration tests over the in-memory reader pass for nested includes, glob order, leading-dot exclusion, missing files, a cycle, depth 17, override confinement and an unreadable include
  - _Depends: 2.2, 2.3_
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10, 1.13_

- [x] 3. Matching hosts and associating keys
- [x] 3.1 (P) Match host patterns with OpenSSH pattern-list semantics
  - Lowercase the candidate, glob `*` and `?`, and let any matching negated pattern veto the whole list
  - Never match a pattern containing upper-case letters, mirroring `ssh`
  - Unit tests pass for wildcards, negation veto, case sensitivity and a list with no positive match
  - _Boundary: SSHHostPatternMatcher_
  - _Requirements: 2.10, 3.3, 6.6, 7.3, 13.4_

- [x] 3.2 (P) Resolve identity file values without a connection
  - Expand tilde first, then `%d`, `%u` and `%%`, and treat the literal `none` as disabled
  - Report connection tokens, environment variables, another user's home and relative paths as unresolvable with the specific reason, never guessing a path
  - Standardise output paths without resolving symbolic links, matching how key discovery compares paths
  - Unit tests pass for every resolvable form and every unresolvable reason
  - _Boundary: IdentityFileResolver_
  - _Requirements: 2.4, 2.5, 2.6, 3.2, 11.4, 13.4_

- [x] 3.3 Associate host entries with discovered key pairs and detect shared keys
  - Associate each identity file with a listed pair when it resolves to the pair's private or public key, and otherwise mark it unlisted, unresolved or disabled; an entry with no identity file yields no associations, which means default identities
  - Group concrete entries by the key they use, ignore pattern entries, and treat entries with identical lowercased pattern sets as one host
  - Answer, per entry, the other hosts sharing its key; per key, the hosts using it, optionally excluding one entry; per file location, the entries that reference it; and whether any reference is unresolved
  - Unit tests pass for a `.pub` reference, differently spelled references to one key, pattern-entry exclusion, a duplicate pattern set, and the warning disappearing once only one host uses the key
  - _Depends: 3.1, 3.2_
  - _Requirements: 2.3, 2.4, 2.5, 2.6, 2.7, 3.1, 3.2, 3.3, 3.8, 4.3, 11.1, 11.2, 13.4_

- [x] 4. Validating and rewriting host blocks
- [x] 4.1 (P) Validate host drafts field by field
  - Reject an empty or whitespace-only alias; on create, reject an alias containing whitespace, a wildcard or a negation, explaining that the form adds one concrete host
  - Reject an alias matching a pattern of another concrete entry and name that entry, excluding the entry being edited
  - Reject a port outside 1–65535 stating the range, any value with a line break, `#` or double quote naming the character, and a host name or user containing whitespace
  - Apply the same rules to edits, except that patterns the block already declares are kept
  - Unit tests pass for every rejection rule in both create and edit mode, each error attached to the right field
  - _Boundary: HostDraftValidator_
  - _Depends: 3.1_
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.9, 13.4_

- [x] 4.2 (P) Format values and identity file arguments for writing
  - Write a value bare when it needs no quoting, otherwise quote it and escape backslashes
  - Write a chosen key's identity file in tilde form when the directory is the default one, otherwise as the absolute private key path
  - Property tests pass showing that every formatted value tokenizes back to exactly the validated value
  - _Boundary: SSHConfigValueFormatter_
  - _Requirements: 4.7, 4.8, 9.1, 13.4_

- [x] 4.3 Apply an edit to one block while preserving every other byte
  - Rewrite only the argument span of the first declaring line for each changed field, keeping indentation, keyword spelling, separator and trailing comment
  - Remove the directive when a value is cleared, and insert a new directive after the block's last directive using the block's, then the file's, indentation, falling back to four spaces
  - Rewrite the `Host` line only when patterns change; leave identity file lines untouched for an unchanged key choice, remove them all for no key, and replace a single resolvable one or insert one for a chosen pair
  - Use the file's dominant terminator for new lines and preserve the final-newline state
  - Tests pass for every fixture: every line outside the edited block is identical and in order, and directives the form does not present keep their value, position and comments
  - _Depends: 4.2_
  - _Requirements: 5.2, 5.3, 5.4, 5.5, 5.6, 9.1, 9.2, 13.6_

- [x] 4.4 Insert a new block, remove a block and produce a new file
  - Insert `Host <alias>` with only the supplied directives in a fixed order, in the file's indentation style, separated from neighbours by exactly one blank line
  - Remove a block's lines together with its directly attached comment lines and one adjacent blank line, so no double blank remains and nothing else changes
  - Produce the contents of a brand-new configuration file that contains only the new block
  - Tests pass for every fixture: insertion and removal leave all other lines identical, and removal never touches a key pair
  - _Requirements: 6.5, 6.11, 8.3, 8.4, 9.1, 9.2, 13.6_

- [x] 4.5 (P) Decide where a new block goes and warn about earlier matches
  - Place the new block before the first `Host` block in `config` that matches the alias, together with that block's attached comments, otherwise append it at the end
  - Never place it above the first `Host` or `Match` line in `config`, and ignore `Match` blocks when choosing
  - Report every matching block earlier in load order, in an included file or the global section, naming its file, and count an include reached under a `Match` block as possibly matching
  - Unit tests pass for `Host *` first or last, a wildcard domain block, a negated pattern, a global `Include`, `Match` first, no host blocks, and a match in an earlier include
  - _Boundary: HostBlockPlacement_
  - _Depends: 2.4, 3.1_
  - _Requirements: 6.6, 6.7, 6.8, 6.9, 6.10, 13.4_

- [x] 4.6 (P) Choose a backup location that `ssh` will never read
  - Derive a hidden backup name beside the resolved file
  - Refuse, with the matching pattern, a backup location that any loaded include path would match
  - Unit tests pass, including a backup refused because an include matches every dotfile
  - _Boundary: ConfigBackupLocation_
  - _Depends: 2.3_
  - _Requirements: 9.4, 13.4_

- [x] 5. (P) Write configuration files safely on disk
  - Replace a file atomically by writing a hidden temporary file in the same directory, applying the original permission bits, flushing and renaming over the target, after confirming the current bytes still equal the expected baseline
  - Follow symbolic links so the link survives, and refuse any target whose resolved location is outside the resolved SSH directory
  - Create a new file with owner-only permissions through an exclusive rename that never replaces a file that appeared concurrently
  - Back a file up with exclusive creation and owner-only permissions, reporting an existing backup as already present rather than overwriting it
  - Remove the temporary file on every failure path, leave the target byte-identical, and run all work off the main actor
  - Scratch-directory tests pass for permission preservation, symlink preservation, an outward symlink refused, exclusive create against an existing file, an expected-bytes mismatch, temporary-file cleanup and completion while the main actor is blocked
  - _Boundary: FileSystemSSHConfigWriter_
  - _Depends: 1.2_
  - _Requirements: 6.12, 9.3, 9.4, 9.5, 9.6, 9.7, 9.9, 9.10, 9.11, 13.1, 13.2_

- [x] 6. Configuration model
- [x] 6.1 Load and present the configuration state
  - Hold a closed state of loading, loaded, no configuration file, unreadable or no directory, plus a single in-flight operation and the latest notice
  - Refresh by re-reading directory status and the configuration, never throwing, waiting until no operation is in flight
  - Mark entries read-only when their file's resolved location lies outside the directory, and compute the key index for any set of discovered pairs
  - Model tests with the in-memory reader pass for each state, partial loads with issues, and an outward symlink making an entry read-only
  - _Requirements: 1.1, 1.8, 1.9, 1.11, 1.12, 1.13, 5.8, 8.6_

- [x] 6.2 Edit and delete host entries with backup and change detection
  - Accept a mutation only when no other is in flight and the entry is writable, and only as the result of a user-confirmed action
  - Compute new bytes from the baseline captured when the form opened, take a backup before the first modification, then replace only the file declaring the block
  - On a changed file, write nothing, report that the file changed and reload; on any failure, report the reason naming the file and leave the original untouched
  - Reload after success and publish a notice naming the host; build the deletion confirmation title and a message naming the entry and its file
  - Model tests with the in-memory writer pass: an edit writes only the declaring included file, an external change produces no write, the backup is taken once, a second mutation is refused while one runs, and deletion never touches a key
  - _Depends: 4.3, 4.4, 4.6, 6.1_
  - _Requirements: 5.7, 5.10, 8.2, 8.3, 8.4, 8.5, 8.7, 9.4, 9.6, 9.7, 9.8, 9.12, 9.13_

- [x] 6.3 Create host entries in `config`
  - Insert the new block into `config` at the placement decision's point, following the same backup, baseline and notice rules as an edit
  - Create `config` with owner-only permissions when it does not exist, without taking a backup
  - Report an absent SSH directory and write nothing
  - Model tests pass for insertion, creation with no `config`, the absent-directory refusal and the new entry appearing after reload
  - _Depends: 4.5_
  - _Requirements: 6.5, 6.12, 6.13, 6.15, 9.8, 9.12, 9.13_

- [x] 6.4 Answer host references for key management
  - Declare the host-reference lookup contract consumed by key management and have the configuration model conform to it
  - Report the hosts whose identity files resolve to a key pair and whether unresolved references exist, or that references could not be checked when the configuration is not loaded
  - Model tests pass for referencing hosts, unresolved references and an unloaded configuration
  - _Requirements: 11.1, 11.2, 11.3, 11.4_

- [x] 7. Host form model
- [x] 7.1 Manage form mode, draft and baseline
  - Present the list when no form is open, or a create or edit form within the Hosts tab
  - Start an edit populated from the entry's patterns, host name, user, port and key, capturing the declaring file's bytes as the baseline; start a create with an empty draft
  - Present repeated `HostName`, `User` or `Port` values, and multiple or unresolvable identity files, as read-only with the reason, keeping them unchanged unless the user replaces the key explicitly
  - Discard the draft and return to the list without writing, and return to the list after a successful save
  - Model tests pass for populating an edit, discarding on cancel, and the read-only cases
  - _Requirements: 5.1, 5.6, 5.9, 5.10, 6.1, 6.2, 6.3, 6.14, 6.15, 10.9_

- [x] 7.2 Offer key choices, validation and the placement warning
  - Offer "no key" plus every discovered pair, offer "unchanged" first and selected when the edit cannot represent its keys, and mark pairs used by other concrete hosts with the hosts' names without asking for further confirmation
  - Present a pair without a private key as unavailable and not selectable, and offer only "no key" with a no-keys statement when none exist
  - Derive field validation and submit availability from the validator on every change rather than storing them
  - In create mode, build a warning naming each earlier matching block and its file so submitting asks for confirmation, and never block submission because of a shared key
  - Model tests pass for every key-choice case, submit availability under each rejection, and the placement warning
  - _Depends: 3.3, 4.1, 6.1_
  - _Requirements: 3.7, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 6.4, 6.10, 7.7, 7.8_

- [x] 8. Panel navigation building blocks and key management cross-references
- [x] 8.1 (P) Add a generic tab bar and the panel tokens it needs
  - Add a segmented tab bar component to the design system that takes caller-supplied options and titles, shows selection by shape and contrast as well as tint, exposes each segment's name and selected state to accessibility, and names no OpenSSH concept
  - Add tokens for the tab bar height, host list height, host detail height and key picker height, and grow the panel height by the tab bar height plus regular spacing
  - Panel sizing tests pass for the new height arithmetic
  - _Boundary: DesignSystem_
  - _Requirements: 10.1, 10.11, 10.14, 12.2, 12.3_

- [x] 8.2 (P) Let the new-key form be discarded without completing
  - Clear entered values and the passphrase without producing a completion, and do nothing while a generation is running so it completes in the background
  - Form model tests pass: discarding drops the passphrase, and discarding mid-generation neither cancels it nor loses its outcome
  - _Boundary: NewKeyFormModel_
  - _Requirements: 10.8, 10.9_

- [x] 8.3 Name referencing hosts when a key is renamed or deleted
  - Inject the host-reference lookup into key management with no default value
  - List referencing hosts in the rename warning and the deletion confirmation, state when unresolved references might name the key, and state when references could not be checked
  - Never modify a configuration file as part of a rename or deletion
  - Key list model tests with a fixed-report test double pass for referencing hosts, unresolved references and unavailability, and existing key list tests pass with the new initializer
  - _Depends: 6.4_
  - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

- [x] 9. Host views
- [x] 9.1 Project host entries into display text
  - Produce each entry's title from its patterns, a summary of user, host name and port, key text per association (pair name, unlisted value, unresolved value, or default identities), the declaring file when not `config`, a pattern-entry marker and the sharing hosts
  - Produce an accessibility label combining all of these and naming the sharing hosts
  - Unit tests pass for each association kind, attribution, pattern entries and the shared-key label
  - _Requirements: 2.2, 2.5, 2.6, 2.7, 2.9, 2.10, 3.4, 3.5, 12.7_

- [x] 9.2 Build the host list and rows
  - Render a section header, the first load issue with a count, a bounded scrolling list of rows, distinct empty states for no hosts and no configuration file, and a detail region with the selected entry's values, keys, file and sharing warning
  - Show the shared-key warning as the design system's warning symbol and colour together, never colour alone
  - Offer New host, Edit and Delete; gate Delete behind the design system's confirming style with the model's title and message, using the destructive appearance; disable Edit and Delete for read-only entries with the reason shown
  - Use design system components and tokens only, with no inline font, spacing, radius or colour and no file access
  - The list renders every state in a preview and an accessibility label exists on every control
  - _Depends: 9.1_
  - _Requirements: 1.8, 1.9, 2.1, 2.12, 2.13, 3.1, 3.4, 3.6, 5.8, 8.1, 8.2, 8.6, 12.1, 12.2, 12.4, 12.5, 12.6, 12.7_

- [x] 9.3 Build the host form and key picker
  - Render alias or patterns and host name as full-width labelled fields, user and port side by side, and read-only fields with their reason in place of editable ones
  - Render a bounded key picker whose rows show availability and the shared-key warning, plus a status line naming the hosts that use the selected key
  - Show field validation inline, keep the submit control unavailable while any value is rejected, and gate submission through the confirming style when a placement warning exists
  - Offer Cancel and Save or Create, using design system components and tokens only, with an accessibility label on every control
  - The form renders create, edit, read-only and warning states in previews
  - _Depends: 7.2_
  - _Requirements: 4.1, 4.3, 4.5, 4.6, 5.1, 5.6, 6.2, 6.4, 6.10, 7.7, 12.1, 12.2, 12.5, 12.6, 12.7_

- [x] 9.4 Switch the Hosts tab between list and form
  - Present the form in place of the list within the tab, keeping the tab bar visible, and return to the list on cancel or completion
  - Observable when selecting create or edit swaps the surface and cancelling returns to the list with no file written
  - _Requirements: 5.9, 6.1, 6.14, 10.10_

- [x] 10. Integration: tabs and composition root
- [x] 10.1 Replace the panel's route navigation with tabs
  - Replace the two-route navigation with a closed tab selection of Keys, Hosts and New Key, starting on Keys
  - Present the key list on Keys, the host surface on Hosts and the existing create-key form on New Key, or the directory status when no directory has resolved
  - Remove the key list's create control and its own refresh, and refresh both keys and configuration each time the panel opens
  - Discard the host form and the new-key form when leaving their tabs, select Keys when a generation completes, and show the active tab's notice
  - Keep every surface at the fixed surface height, the Quit control and its shortcut outside the tabs, and lay out without AppKit layout recursion
  - Tab logic tests pass for the initial tab, leaving New Key mid-generation, leaving it otherwise, and completion selecting Keys
  - _Depends: 8.1, 8.2, 9.4_
  - _Requirements: 1.11, 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7, 10.8, 10.9, 10.11, 10.12, 10.13_

- [x] 10.2 Wire the configuration feature in the composition root
  - Construct the file-system configuration writer, the configuration model before key management, and the host form model, injecting the home directory and user name
  - Start the configuration load at launch once the directory resolves, honouring an override directory and never falling back to the home directory
  - Observable when the app builds and a launch with an override directory lists that directory's hosts in the Hosts tab
  - _Depends: 6.3, 8.3, 10.1_
  - _Requirements: 1.1, 9.10, 13.3_

- [x] 11. Validation and regression
- [x] 11.1 Extend the safety tests to configuration writing
  - Assert that every path a create, edit or delete touches lies within the resolved directory, that an override confines writes, and that nothing is written without a confirmed action
  - Extend the source scans so file-system access stays in the file-access layer, no networking interface appears, and no test names the home directory or a literal SSH directory path
  - Safety suites pass with the configuration feature included
  - _Requirements: 9.8, 9.9, 9.10, 9.12, 9.14, 13.1, 13.2, 13.3_

- [x] 11.2 Verify panel sizing, appearance and text scaling
  - Measure every tab surface and host surface at the default and largest text sizes, in light and dark appearance
  - Sizing tests pass, showing switching tabs never changes the panel size
  - _Requirements: 10.11, 10.12, 12.8_

- [x] 11.3 Run the full test suite
  - Run the build and the test target for a macOS destination and fix any regression
  - Observable when `xcodebuild … test` passes with no failures
  - _Requirements: 13.7_
