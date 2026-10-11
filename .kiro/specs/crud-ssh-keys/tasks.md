# Implementation Plan

**Prerequisite**: the `design-system` spec must ship before task 4 begins, including its
Requirements 3.9 to 3.11 (confirming button style with a caller-supplied title and message).
Tasks 1 to 3 have no dependency on it and can proceed in parallel with its implementation.

## 1. Foundation: domain values, port contracts and test doubles

- [x] 1.1 (P) Model key types so only applicable parameters are expressible
  - Represent Ed25519, RSA and ECDSA as a closed set in which each case carries only its own parameters, so an Ed25519 value cannot hold a bit length and an RSA value cannot hold a curve
  - Offer 2048, 3072 and 4096 for RSA and the three NIST curves for ECDSA, enumerable so no later call site lists them
  - Own the `ssh-keygen` argument spelling for each case so no caller assembles flags
  - Carry the generation request as name, type and comment, holding no secret
  - Observable: a test asserts every type-and-parameter combination the generator accepts, and an invalid pairing fails to compile
  - _Boundary: SSHKeyType, SSHKeyGenerationRequest_
  - _Requirements: 8.3, 8.4, 8.5, 9.1_

- [x] 1.2 Validate key names so an unusable name cannot be constructed
  - Reject empty and whitespace-only names, path separators and anything resolving outside the directory, a `.pub` suffix, and the names OpenSSH reserves
  - Reject a name whose derived files — private, public and certificate — would replace any existing entry, naming the file that would have been replaced
  - Accept a rename that keeps its current name without reporting a self-collision
  - Expose the validated name as the only way to obtain one, so an unchecked name has no construction path
  - Observable: a test supplies a fabricated directory listing and gets a distinct typed rejection for each rule, with no file system access
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.8_

- [x] 1.3 (P) Hold a passphrase as a value that cannot be printed
  - Keep the entered secret in private storage and render it as a redacted marker under both description protocols, so reflection cannot leak it into an interpolated message
  - Refuse serialisation entirely, and expose a single accessor for the generator
  - Carry "no passphrase" as a value rather than a sentinel
  - Claim no memory scrubbing: the obligation is retaining no reference, which is what a value type can discharge
  - Observable: a test interpolates the value into a string and finds the marker rather than the secret
  - _Boundary: Passphrase_
  - _Requirements: 10.4, 10.7, 10.8_

- [x] 1.4 Model a key pair and its parsed public key
  - Represent a pair as its name, its public key file, an optional private key file and an optional certificate file, so an absent private key is data rather than an error
  - Represent the parsed public key as algorithm, size, fingerprint and an optional comment, keeping an absent comment distinguishable from an empty one
  - Represent the parse outcome so an unreadable public key is an explicit state on the entry rather than a dropped entry
  - Indicate that a pair carries a certificate
  - Observable: a test constructs a pair whose public key failed to parse and one whose private key is absent, and both are representable without optionals standing in for errors
  - _Requirements: 1.3, 1.6, 2.1, 2.4, 2.5, 2.6_

- [x] 1.5 (P) Define the mutation and generation error vocabularies
  - Separate an existing destination, absence, denial and an unclassified failure for file mutation, each carrying the path it concerns
  - Separate an unavailable tool, a missing directory, a tool failure, missing output, a mismatched generated key and a timeout for generation
  - Expose a user-facing reason on each, following the existing file-access error precedent, so no error object ever reaches a view
  - Exclude any passphrase or private key path from every reason
  - Observable: a test asserts each case produces a reason naming its condition, and none contains a secret
  - _Boundary: SSHKeyWriteError, SSHKeyGenerationError_
  - _Requirements: 4.6, 7.6, 9.5, 9.6, 9.7, 10.8_

- [x] 1.6 Declare the three port contracts
  - Declare file mutation as move and remove only, with no create, so the only path that brings a file into existence is OpenSSH itself
  - Declare key generation taking a request, a passphrase and the target directory, returning the pair it produced
  - Declare clipboard writing taking already-read text, so it has no way to reach a file
  - Leave the existing read-only directory port untouched and unwidened
  - Observable: the project builds with the three contracts declared and the read port unchanged
  - _Requirements: 3.5, 10.1, 11.7_

- [x] 1.7 Provide test doubles for the three ports
  - Record every move and removal, and allow a chosen path to fail, so rollback can be driven deterministically
  - Return a fabricated generation outcome without launching any process
  - Record what reached the clipboard
  - Follow the existing support conventions: immutable values or internally locked, safe under parallel suites, and no reference to the home directory or any literal SSH directory path
  - Observable: the existing suite still passes with the doubles present, and a smoke test drives each double
  - _Requirements: 14.1, 14.2, 14.3, 14.4_

## 2. Core: pure rules

- [x] 2.1 (P) Derive every presented attribute from the public key file
  - Split a public key line into at most three fields so a comment containing spaces survives intact
  - Treat the algorithm name inside the key blob as authoritative rather than the line's first field
  - Compute the fingerprint as the padded-stripped base64 of the blob's SHA-256 digest, prefixed to match OpenSSH's own output
  - Derive size from the modulus for RSA, the curve name for ECDSA and a constant for Ed25519
  - Read nothing but the public key bytes, and never trap on malformed, truncated or non-base64 input
  - Observable: a test asserts the fingerprint, algorithm, size and comment for Ed25519, RSA and ECDSA fixtures match what OpenSSH reports, and malformed input returns a typed failure
  - _Boundary: SSHPublicKeyParser_
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 14.5_

- [x] 2.2 (P) Discover key pairs from a directory listing
  - Derive one pair per public key file, treating the sibling without the extension as the private key when present and reporting it absent otherwise
  - Exclude the configuration, known-hosts and authorized-keys files and any directory
  - Attach a certificate file to the pair whose name it extends rather than listing it as an entry
  - Order entries by name so the presentation is stable across refreshes
  - Perform no file system access whatsoever, so the rule is exercised entirely from a supplied listing
  - Observable: a test supplies a fabricated listing containing all of these cases and gets the expected pairs, with no port call made
  - _Boundary: SSHKeyDiscovery_
  - _Requirements: 1.2, 1.3, 1.4, 1.5, 14.5, 14.6_

- [x] 2.3 (P) Plan a rename as an ordered set of moves with an inverse
  - Produce the moves for private key, public key and certificate when present, so all files continue to share one base name
  - Derive the public key's destination by appending the public extension to the private key's destination
  - Produce the inverse of any prefix of the plan's own steps, which is what a failed rename executes
  - Keep every destination inside the pair's own directory and modify no file contents
  - Observable: a test asserts the ordering, the derived public destination, and a correct inverse for every prefix length
  - _Boundary: SSHKeyRenamePlan_
  - _Requirements: 4.2, 4.3, 4.4, 11.1_

- [x] 2.4 (P) Plan a deletion as an ordered set of removals
  - Produce the removals for private key, public key and certificate when present
  - Restrict the plan to files belonging to the pair the caller identified, so no bystander file can appear in it
  - Observable: a test asserts a pair with a certificate yields three removals and a pair without yields two, and that no path outside the pair is ever included
  - _Boundary: SSHKeyDeletePlan_
  - _Requirements: 7.3, 7.7, 11.2_

## 3. Core: adapters

- [x] 3.1 (P) Mutate files through the single write adapter
  - Implement move and remove against the real file system, as the only new code permitted to use the file manager
  - Rely on the platform's refusal to replace an existing destination rather than checking first, so a bystander file cannot be destroyed even by a defective validator
  - Preserve each moved file's existing permissions
  - Translate platform failures into the mutation vocabulary, consulting both the framework code and the underlying system error so absence stays distinguishable from denial
  - Keep the work off the main actor using the type-level and method-level isolation combination the existing reader documents, since the type-level annotation alone is insufficient
  - Observable: a scratch-directory test confirms permissions survive a move, an existing destination is refused with the contents intact, and a mutation completes while the main actor is blocked
  - _Boundary: FileSystemSSHKeyWriter_
  - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.6_

- [x] 3.2 (P) Place a public key on the clipboard
  - Write the supplied text as a single line, byte for byte, with no trailing newline
  - Keep the pasteboard framework out of every view by confining it to this adapter
  - Neither clear nor expire the clipboard afterwards, since a public key is not a secret
  - Observable: a test drives the adapter through its port and asserts the recorded text matches the source line exactly
  - _Boundary: PasteboardClipboardWriter_
  - _Requirements: 3.1, 3.2, 3.6_

- [x] 3.3 (P) Generate a key pair through ssh-keygen without exposing the passphrase
  - Launch the tool at an absolute injected path rather than resolving through the search path, so a hijacked path cannot substitute the binary that receives the passphrase
  - Supply the passphrase on piped standard input, writing one buffer twice and then closing the stream, so the two prompts cannot receive different values and the silent downgrade to an unencrypted key is unreachable
  - Place no secret in the argument list or the environment
  - Drain both output streams concurrently with the wait so a prompt cannot fill a pipe and deadlock, and bound the whole operation with a timeout
  - Report an unavailable tool and a missing target directory as distinct conditions, and leave no partially written file behind on failure
  - Observable: tests against a stub executable confirm the passphrase reaches standard input and appears in neither the arguments nor the environment, a non-zero exit maps to a tool failure, and a non-terminating stub hits the timeout
  - _Boundary: ProcessSSHKeyGenerator_
  - _Requirements: 9.1, 9.2, 9.5, 9.6, 9.7, 10.5_

- [x] 3.4 Accept a generated pair only on evidence, not exit status
  - Require all three of a successful exit, both files present, and a parsed public key whose algorithm and size match what was requested
  - Report a mismatch as its own condition, since a check of file presence alone would still pass a key of the wrong type
  - Rely on the tool's own output permissions rather than setting them, which already match what the command line produces
  - Observable: a test whose stub exits zero while writing a key of the wrong type is rejected, and one writing no file at all is rejected with a distinct reason
  - _Depends: 2.1, 3.3_
  - _Requirements: 9.2, 11.3_

## 4. Foundation for the panel: sizing spike and shell

- [ ] 4.1 Verify that an exactly-sized panel does not resize or recurse
  - Build a throwaway panel at an exact fixed height containing a list longer than itself, and exercise it across repeated opens and a simulated surface switch, run against a scratch directory through the launch override
  - Confirm no layout-recursion diagnostic appears and the panel does not shrink on the second or later open
  - If the scrolling container still collapses inside an exactly-sized container, substitute a bounded lazy stack — this fallback is pre-authorised and needs no further decision
  - Observable: a recorded result stating which container was adopted, with the panel holding one size across at least three consecutive opens
  - _Requirements: 12.5, 12.6, 12.7_

- [ ] 4.2 Host both surfaces in a fixed-size panel behind a closed route
  - Give the panel an exact fixed height so no surface is content-sized, using whichever container task 4.1 settled on
  - Represent the route as a closed pair of cases, so neither surface can be absent or presented twice
  - Keep the menu bar scene the only scene, and retain the existing quit control and its shortcut outside any scrolling region
  - Return from the form to the list without requiring the panel to be reopened
  - Observable: switching the route leaves the panel's width and height unchanged, verified by a real launch against a scratch directory
  - _Depends: 4.1_
  - _Requirements: 12.1, 12.4, 12.5, 12.8_

## 5. Core: presentation models

- [x] 5.1 Present the key list and distinguish its failure states
  - Enumerate the resolved directory on each panel open, pair the results and parse each public key, presenting one entry per pair
  - Keep "no keys found" and "could not be read" as separate states, so an unreadable directory never presents as an empty list
  - Degrade a single unreadable or unparseable entry while presenting every other pair
  - Take no dependency with a default value, so a missing injection fails to compile rather than falling back to the real file system
  - Place every presentation projection on the value rather than the view, following the existing status projection
  - Re-enumerate after any completed mutation, and stay responsive while enumerating
  - Observable: tests drive an empty directory, an unreadable directory, and a directory with one corrupt public key, and each produces its own distinct presented state
  - _Requirements: 1.1, 1.7, 1.8, 1.9, 1.10, 2.6_

- [x] 5.2 Copy a public key on demand
  - Read the selected pair's public key file and place its contents on the clipboard through the port
  - Confirm a completed copy to the user
  - Report the reason and leave the clipboard untouched when the file cannot be read
  - Never place a private key file's contents on the clipboard, which the port makes structurally impossible since it is handed text rather than a path
  - Observable: a test asserts the recorded clipboard text matches the file, and that a read failure leaves the recorder empty
  - Not parallel with 5.1, 5.3 or 5.4 despite the separate concern: all four extend the same list model, so they contend on one file
  - _Depends: 3.2_
  - _Requirements: 3.3, 3.4, 3.5_

- [x] 5.3 Rename a pair as a unit, restoring every file on failure
  - Offer the pair's current name for editing, validate it, and keep the confirming control unavailable and every file unchanged while it is rejected
  - Warn that references to the previous path are not updated, naming both paths, and require the user to proceed explicitly before anything moves
  - Execute the planned moves, and on any failure restore every file already moved and report the reason — or, if restoration itself fails, name every path still out of place
  - Modify no file contents, including the comment inside the public key, and modify nothing outside the renamed pair
  - Hold the in-flight operation as a closed state with no case for two, so a second mutation cannot begin
  - Observable: a test failing the second of three moves leaves every file at its original name; a test failing a restoration names the paths left out of place
  - _Depends: 2.3, 3.1_
  - _Requirements: 4.1, 4.4, 4.5, 4.6, 4.7, 5.6, 5.7, 6.1, 6.2, 6.3, 6.5, 11.5, 11.7_

- [x] 5.4 Delete a pair behind an unsuppressable confirmation
  - Request confirmation before removing anything, supplying a title and message that name the pair and state that the removal is permanent
  - Remove the private key, the public key and any certificate, and drop the entry from the list
  - Leave every file unchanged when the user does not confirm
  - Name the files that remain when a removal fails
  - Require a separate confirmation for each deletion and offer no way to suppress it
  - Act only on a pair the user identified through a presented entry
  - Observable: a test declining the confirmation performs no removal; a test failing the second removal names the remaining files
  - _Depends: 2.4, 3.1_
  - _Requirements: 7.1, 7.2, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9_

- [x] 5.5 Hold and validate the create form's state
  - Collect a file name, a key type, a comment and a passphrase, proposing a default name and comment the user can replace
  - Present only the selected type's parameters, discarding any that no longer apply when the type changes
  - Require the passphrase twice and report a mismatch before generation is attempted, which is the only place a mismatch can be caught given the generator writes one buffer twice
  - State that an empty passphrase leaves the private key unencrypted, and allow it
  - Derive the generate control's availability rather than storing it, indicating which value is invalid while any is
  - Own the reveal flag for the redacted fields, since the component reports a request and does not act on it
  - Discard every entered value on cancel without writing any file, and retain no passphrase reference on any exit path
  - Observable: tests assert a mismatched pair blocks submission, changing the type clears an inapplicable parameter, and cancelling writes nothing
  - _Depends: 1.2, 1.3_
  - _Requirements: 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.9, 8.10, 10.6, 10.7_

- [x] 5.6 Run generation from the form and present its outcome
  - Present progress and keep the generate control unavailable while generation runs
  - Return to the list on success and present the new pair with the type, size and comment that were requested
  - Own the generation task on the model rather than a view's lifetime, so dismissing the panel does not cancel it and the outcome is presented when the panel is next opened
  - Report the reason on failure and leave the directory unchanged
  - Observable: tests drive success, an unavailable tool, a mismatched output and a missing directory through the stub generator without launching a process
  - _Depends: 3.4, 5.5_
  - _Requirements: 9.3, 9.4, 9.8_

## 6. Integration: views, wiring and showcase removal

- [ ] 6.1 Render the key list from design system components
  - Present entries through the composite list and list row components, headings through the section header, and the fingerprint and paths through the code text component
  - Present per-entry and operation state through the status indicator, and key attributes as labelled rows
  - Present "no keys found" through the empty-state component rather than an empty rows area
  - Declare no font, spacing, radius or colour value inline, and add a token rather than a literal where no token exists
  - Reach no file system and obtain every displayed value from the injected model
  - Observable: the running panel lists the keys in a scratch directory with no inline styling value anywhere in the view sources
  - _Depends: 4.2, 5.1_
  - _Requirements: 1.7, 13.1, 13.2, 13.3, 13.5, 13.6_

- [ ] 6.2 Render the rename and delete surfaces through the confirming button style
  - Gate both destructive actions through the design system's confirming button style, supplying the title and message rather than building a confirmation flow here
  - Present destructive controls in the destructive appearance
  - Present the rename name entry through the composite field component, showing its validation message without changing the surface's height
  - Observable: a real launch confirms neither action proceeds until confirmed, and that the confirmation names the key pair
  - _Depends: 5.3, 5.4, 6.1_
  - _Requirements: 6.1, 7.1, 7.9, 13.4, 13.5_

- [ ] 6.3 Render the create form
  - Present the form in place of the list when the create control is activated
  - Present the name and comment fields through the text field components, the type and parameter choice through the enumerated-choice component, and both passphrase fields through the secret field component
  - Expose an accessibility label for every control, convey no key state by colour alone, and render legibly in both appearances while scaling with the user's text size
  - Observable: a real launch generates a key into a scratch directory through the form, and the form renders correctly in both light and dark appearance at an increased text size
  - _Depends: 5.6, 6.1_
  - _Requirements: 8.1, 10.6, 13.7, 13.8, 13.9_

- [ ] 6.4 Wire the new ports and models in the composition root
  - Construct the three new adapters and the two models in the single composition root, which stays the only place that constructs an adapter
  - Pass the resolved directory so every mutation is confined to it, including under the launch override, with no fallback to the home directory
  - Keep presenting the resolved directory and its reachability alongside the key list
  - Observable: a launch with the directory override performs every operation inside the override and touches nothing in the real SSH directory
  - _Depends: 6.1, 6.2, 6.3_
  - _Requirements: 11.8, 12.9_

- [ ] 6.5 Remove the design system showcase
  - Present the key list in the panel in place of the showcase
  - Delete the showcase's source files, which that spec confined so their removal needs no edit to any design system file
  - Observable: the showcase sources are gone, the panel opens on the key list, and the build and test suite still pass
  - _Depends: 6.4_
  - _Requirements: 12.2, 12.3_

## 7. Validation

- [x] 7.1 (P) Assert the mutation safety guarantees directly
  - Assert every created, moved and removed path lies inside the resolved directory
  - Assert no existing file outside the identified pair is replaced or removed
  - Assert a multi-file operation that cannot complete leaves the directory as it was
  - Assert no write occurs except as the direct result of a confirmed rename, deletion or creation
  - Observable: a suite covering containment, bystander safety, atomicity and write-provenance passes
  - _Boundary: FileSystemSSHKeyWriter, SSHKeyListModel_
  - _Requirements: 11.1, 11.2, 11.5, 11.7, 11.8_

- [x] 7.2 (P) Assert that key material and passphrases do not escape
  - Assert no code path reads or displays a private key file's contents
  - Assert nothing in the feature transmits any file off the device
  - Assert no passphrase reaches a file, a log, an argument list, an environment or any error reason
  - Observable: a suite covering each of these passes, including the stub-executable assertion that the arguments and environment carry no secret
  - _Boundary: SSHPublicKeyParser, ProcessSSHKeyGenerator, Passphrase_
  - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.8_

- [ ] 7.3 Confirm the panel holds one size through every flow
  - Exercise repeated opens, a route switch in both directions, a list longer than the panel, and a mutation that changes the list's length, against a scratch directory through the launch override
  - Confirm no layout-recursion diagnostic appears and the panel's size never changes
  - Observable: a recorded pass across all four scenarios, with the panel one fixed size throughout
  - _Depends: 6.5_
  - _Requirements: 12.5, 12.6, 12.7_

- [ ] 7.4 Bring the whole suite green on a macOS destination
  - Run the project's build and test commands for a macOS destination
  - Confirm no test names the home directory or a literal SSH directory path, and that the test target still has no host application
  - Observable: the build succeeds and the test target passes
  - _Depends: 7.1, 7.2, 7.3_
  - _Requirements: 14.3, 14.4, 14.7_

## Intentionally Deferred

- **Requirement 6.4** — listing the host entries whose identity file names the key being
  renamed — has **no task**. It is `Where`-gated on SSH configuration reading, which does not
  exist and belongs to a later spec. Requirement 6.1's warning carries the user-facing
  obligation in the meantime. The note under Requirement 6 in `requirements.md` records why a
  rename warns rather than rewriting the configuration, and what opt-in is reserved for the
  spec that adds the parser. Activating 6.4 is a revalidation trigger on this spec.

## Implementation Record — code complete, launch verification outstanding

Tasks 1 to 3, 5, 7.1 and 7.2 are complete and verified by the suite: **357 tests in 39
suites pass** on a macOS destination.

Tasks **4.1, 4.2, 6.1 to 6.5, 7.3 and 7.4 are implemented but left unchecked**, because each
one's observable is stated as a real launch with the panel opened. A `MenuBarExtra` panel can
only be opened by clicking its menu bar item, and that cannot be driven from here: `osascript`
is refused assistive access, so the panel never opens. What was verified instead, and what is
left, is recorded below.

### Verified without opening the panel

- The app launches under `--ssh-directory`, resolves the override, reads it, and writes
  nothing; no diagnostic of any kind is emitted (`panel-run.log` was empty).
- `PanelSizingTests` asserts, through `ImageRenderer`, that both surfaces are *explicitly*
  sized, that they are the same size, and that the panel is exactly its token height. That is
  the mechanism 12.5 to 12.8 depend on, and it now also asserts that a surface is laid out
  inside the panel's gutter rather than across it. It does **not** prove the content fits
  without clipping, nor that no layout-recursion diagnostic appears across repeated opens.
- `MutationSafetyTests` and `KeyMaterialSafetyTests` assert containment, bystander safety,
  atomicity against a real scratch directory, write provenance, and that no private key is
  read and no passphrase reaches a file, an argument list, an environment or a reason.
- No view source declares a font, spacing, radius or colour literal (6.1's second clause).
- The showcase sources are deleted and the build and suite still pass (6.5's first and third
  clauses).
- No test source names the home directory or a literal SSH directory path, and
  `project.pbxproj` declares neither `TEST_HOST` nor `BUNDLE_LOADER` (7.4's two clauses).

### 4.1 — the container question, answered

The spike's purpose was to decide between a scrolling container and the pre-authorised
bounded lazy stack. **The scrolling container was adopted**: the key list renders through the
design system's `BoundedList`, which is a `List` at an explicit frame height, inside a surface
that is itself an exact height. Nothing collapsed and no fallback was needed. The remaining
clause — one size across at least three consecutive opens — needs the panel opened.

### Measured surface heights

A bound `frame` reports its bound whatever is inside it, so the suite cannot assert that a
surface fits. Measuring it needs `height:` deleted from the surface's own `frame` and the
result rendered through `ImageRenderer`. Done once, by hand, at the default text size:

| Surface | Wants | Bound |
| --- | --- | --- |
| Key list, 1 to 12 keys | 438 | 448 |
| Key list, empty | 310 | 448 |
| Create form | 383 | 448 |
| Whole panel | 525 | 548 |

`surfaceHeight` was 420 and clipped the key list by 18 points; it is now 448. The panel's
remaining 23 points are deliberate headroom, because every region is a fixed height and a
larger text size has to grow into something — the first region it would otherwise clip is
Quit. **This is the number 6.3's increased-text-size check is really testing**, and it is
the one measurement that will need redoing whenever either surface gains a row.

### What is left to do, by hand

```bash
xcodebuild -project open-ssh-gui.xcodeproj -scheme open-ssh-gui -destination 'platform=macOS' build
SCRATCH=$(mktemp -d)
(cd "$SCRATCH" && for i in 1 2 3 4 5 6 7 8; do ssh-keygen -q -t ed25519 -C "user$i@host" -N "" -f "key_$i"; done)
~/Library/Developer/Xcode/DerivedData/open-ssh-gui-*/Build/Products/Debug/open-ssh-gui.app/Contents/MacOS/open-ssh-gui \
  --ssh-directory "$SCRATCH" 2>&1 | tee /tmp/panel.log
```

Then, with the panel open, confirm and check off:

- **4.1, 4.2, 7.3** — open the panel at least three times; switch to the create form and back
  in both directions; select a key, delete one so the list's length changes. The panel's width
  and height never change, and `/tmp/panel.log` never mentions `_NSDetectedLayoutRecursion`.
- **6.1** — the eight keys are listed, and the selected key's type, size, comment and
  fingerprint read correctly; compare the fingerprint against `ssh-keygen -lf`.
- **6.2** — neither Delete nor Rename proceeds until the second activation, and the
  confirmation names the key pair.
- **6.3** — generate a key through the form; it appears in the scratch directory with the
  type, size and comment supplied. Check it in both light and dark appearance at an increased
  text size.
- **6.4** — nothing in the real `~/.ssh` changed.
- **6.5** — the panel opens on the key list.
- **7.4** — re-run the build and test commands after any change the above prompts.
