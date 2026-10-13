# Research & Design Decisions — crud-ssh-keys

---
**Purpose**: Capture discovery findings, architectural investigations, and rationale that inform the technical design.
---

## Summary

- **Feature**: `crud-ssh-keys`
- **Discovery Scope**: Complex Integration — first write path, first subprocess, first in-panel navigation
- **Key Findings**:
  1. Every public key attribute Requirement 2 asks for is derivable **in-process** from the `.pub` file. Verified byte-for-byte against `ssh-keygen -l`. No subprocess per key, no private key read.
  2. The passphrase reaches `ssh-keygen` through **piped stdin**, so nothing appears in argv. The silent-downgrade hazard found during gap analysis is made **unreachable by construction** rather than detected afterwards.
  3. `MenuBarExtra(.window)` has a documented content-sizing defect. The panel therefore takes an **exact fixed height**; `NavigationStack` is rejected in favour of a closed route enum.
  4. `FileManager.moveItem` preserves POSIX permissions and refuses an existing destination, giving Requirements 11.4 and 11.2 a structural backstop.

---

## Research Log

### Public key metadata: parse in-process or shell out to `ssh-keygen -l`?

- **Context**: Gap analysis R1. Requirement 2.1 wants type, size, fingerprint and comment; Requirement 2.2 forbids reading the private key; Requirement 14.6 wants discovery testable from a supplied listing with no file-system access.
- **Sources consulted**: `ssh-keygen(1)`, `sshd(8)` AUTHORIZED_KEYS FILE FORMAT, RFC 4253 §6.6 (public key blob encoding), direct experiment on macOS 27.
- **Findings**: A public key line is three space-separated fields — algorithm, base64 blob, optional comment — where the comment itself may contain spaces, so the line splits into **at most** three parts. Everything needed sits in the blob, which is a sequence of length-prefixed fields:

  | Attribute | Derivation | Verified |
  |---|---|---|
  | Fingerprint | `"SHA256:" + base64(SHA256(blob))`, `=` padding stripped | Matched `ssh-keygen -l` exactly for Ed25519, RSA-3072, ECDSA-384 |
  | Algorithm | First length-prefixed field inside the blob (`ssh-ed25519`, `ssh-rsa`, `ecdsa-sha2-nistp384`) | Matched the parenthesised type in `ssh-keygen -l` |
  | Size, RSA | Bit length of the modulus `n`, the third mpint | 3072 for a key `ssh-keygen` reported as 3072 |
  | Size, ECDSA | Curve name in the second field (`nistp384`) | 384 |
  | Size, Ed25519 | Constant 256 | 256 |
  | Comment | Third line field, absent when the line has two fields | Preserved including embedded spaces |

- **Implications**: **Parse in-process.** Shelling out would cost one subprocess per key per refresh and would make Requirement 14.6 unreachable, since the parse would no longer be a pure function. The algorithm name appears both outside and inside the blob; the design treats the **in-blob** name as authoritative, since that is what OpenSSH itself verifies against. Line-structure parsing and a SHA-256 digest are not cryptographic implementation — Requirement 9.2's prohibition is on key *generation*, which stays with `ssh-keygen`.

### Supplying a passphrase without exposing it in argv

- **Context**: Requirement 10.5. `ssh-keygen -N <passphrase>` would place the secret in a process listing.
- **Sources consulted**: `ssh-keygen(1)` (`-N`, `-P`), `ssh-add(1)` (`SSH_ASKPASS`, `SSH_ASKPASS_REQUIRE`), direct experiment.
- **Findings**: Three mechanisms exist; piped stdin was verified to work.

  | Mechanism | Result |
  |---|---|
  | Piped stdin, no `-N` | **Works.** No tty required. Key confirmed encrypted via `ssh-keygen -y -f k -P <pass>`. Nothing in argv. |
  | `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE=force` | Would work, but needs a helper executable in the bundle for no additional benefit |
  | `-N <passphrase>` | Rejected — violates 10.5 |

- **Two hazards found by probing**:
  1. **Silent passphrase downgrade.** Piping two *different* lines makes `ssh-keygen` print "Passphrases do not match. Try again.", re-prompt, reach EOF, and generate an **unencrypted** key — while still exiting 0.
  2. **Overwrite prompt.** An existing target produces `Overwrite (y/n)?`; with closed stdin it declines and exits 1.
- **Implications**: The design does not try to *detect* the downgrade. It makes it **unreachable**: the generator writes one passphrase buffer twice to stdin, so the two lines cannot differ, and Requirement 8.7 validates the match in the form before submission. Requirement 5.5's pre-flight collision check means the overwrite prompt is never reached, and stdin is closed after the write so no prompt can block indefinitely. Exit status alone is not trusted as success — see the acceptance gate in the design's generation flow.
- **Also confirmed**: `ssh-keygen` lives at `/usr/bin/ssh-keygen`; exit 1 for a non-existent target directory (Requirement 9.7); produced permissions are `0600` private and `0644` public (Requirement 11.3); RSA-4096 completes in ~0.35s, so Requirement 9.3's progress presentation is about honesty rather than duration.

### Panel navigation and sizing

- **Context**: Gap analysis R3. Commit `c38363c` records `_NSDetectedLayoutRecursion` from a mid-layout height change under `menuBarExtraStyle(.window)`. Requirements 12.5–12.7 add a second surface with a very different natural height.
- **Sources consulted**: Apple Developer Forums thread 741601, `MenuBarExtraStyle.window` documentation, FluidMenuBarExtra's stated rationale.
- **Findings**: The `.window` style has an acknowledged content-sizing defect: a `ScrollView` inside it lays out correctly on first open and collapses to a smaller height on subsequent opens. The forum thread reports that `.frame(maxHeight:)` **does not** fix it, and that `.fixedSize(horizontal: false, vertical: true)` does — but that modifier sizes the view to its full content, which defeats a bounded scrolling list. The style is independently described as using a "less-than-ideal resizing mechanism".
- **Implications**: **Give the panel an exact fixed height** and let both surfaces scroll inside it. Nothing then depends on content height, so neither the sizing defect nor layout recursion can be triggered — the same strategy as the existing `reservedStatusHeight`, generalised from one row pair to the whole panel. **`NavigationStack` is rejected**: its behaviour inside a content-sized `NSPanel` is undocumented, it is the change most likely to reintroduce the recursion, and a closed route enum is both testable and consistent with the project's preference for making invalid states unrepresentable.

### File mutation semantics

- **Context**: Requirements 11.2 and 11.4, and the rollback obligation in 4.6.
- **Sources consulted**: `FileManager.moveItem(at:to:)` behaviour, direct experiment in Swift.
- **Findings**: A move within one directory preserves POSIX permissions (`0600` stayed `0600`), and an existing destination is **refused** with `NSCocoaErrorDomain` 516 (`NSFileWriteFileExistsError`) rather than clobbered; the destination's contents were intact afterwards.
- **Implications**: Requirement 11.4 needs no explicit permission handling on the rename path. Requirement 11.2 gains a structural backstop beneath the pre-flight check in 5.5: even a defective validator cannot destroy a bystander file through this path. Because each move is individually reversible, rollback is an ordered sequence of inverse moves rather than a transaction.

---

## Architecture Pattern Evaluation

The project's pattern is fixed by `tech.md` — layered ports and adapters with a single composition root. The open questions were about placement and granularity.

| Option | Assessment |
|---|---|
| Widen `SSHDirectoryReading` with write methods | **Rejected.** `tech.md`: "A feature that must write declares a separate writing port; this one is never widened." Every existing read-only consumer would gain destructive capability. |
| One `SSHKeyManaging` port covering files, process and clipboard | **Rejected.** Violates interface segregation; a component that only copies a public key would hold deletion and generation. |
| Three narrow ports, placed by capability | **Selected.** `SSHKeyWriting` (file mutation), `SSHKeyGenerating` (process), `ClipboardWriting` (pasteboard). Each gets one fake, so Requirement 14 falls out of the structure. |
| `KeyManagement/` vertical slice | **Rejected.** `structure.md`: layers are not feature folders; a slice makes the dependency direction unverifiable by inspection. |
| New `Platform/` layer for non-file ports | **Selected.** `structure.md` reserves `FileAccess/` as the only place permitted to import `FileManager`. A process port and a pasteboard port are ports and adapters that are not file access, so they need a sibling rather than a tenancy in `FileAccess/`. |

A deliberate consequence of this split: **`SSHKeyWriting` exposes move and remove but no create.** The only code path that brings a file into existence is `ssh-keygen` itself, which is the strongest available expression of `product.md`'s "defers to OpenSSH" commitment.

---

## Design Decisions

| Decision | Rationale | Rejected alternative |
|---|---|---|
| Parse public keys in-process | Pure function, no subprocess per key, satisfies 14.6 | `ssh-keygen -l` per key |
| Piped stdin for the passphrase, same buffer written twice | Satisfies 10.5; makes the downgrade unreachable rather than detected | `-N`; `SSH_ASKPASS` helper |
| Success requires exit 0 **and** both files present **and** the parsed public key matching the request | Exit status is demonstrably not sufficient | Trusting exit status |
| Exact fixed panel height, both surfaces scrolling inside | Removes content-dependent sizing, so the `.window` defect and layout recursion are both unreachable | `maxHeight` (documented not to work); `fixedSize` (defeats bounded scrolling) |
| Closed `PanelRoute` enum | Testable, unrepresentable invalid states, no untested panel interaction | `NavigationStack` inside the panel |
| Absolute `ssh-keygen` path, injected with no default | A `PATH` lookup lets a hijacked `PATH` substitute the binary that handles the user's passphrase | `PATH` resolution |
| Pure plan types for rename and delete, thin execution | Ordering and rollback become unit-testable without a file system | Imperative sequence inside the model |
| `SSHKeyType` as an enum with associated parameters | Makes `.ed25519` carrying a bit length a compile error, satisfying 8.5 structurally | Struct with optional `bits` and `curve` |
| Passphrase as a redacting value type | Satisfies 10.8 — reflection cannot leak it into an error message or log | Passing `String` |

---

## Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| `ssh-keygen` prompts unexpectedly and the subprocess blocks | High | stdin closed after the passphrase write; stdout and stderr drained concurrently; a timeout fails the generation |
| Rollback itself fails mid-way | High | Rollback is inverse moves within one directory, which `moveItem` makes individually reversible; a failed rollback reports every path still out of place |
| `.window` sizing defect resurfaces | Medium | Exact fixed height; no surface is content-sized |
| `Process` under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` silently runs on the main actor | Medium | `nonisolated` type plus `@concurrent` methods, mirroring `FileSystemSSHDirectoryReader`, whose test already guards the pattern |
| Design system not yet shipped | High | Hard prerequisite, recorded in the design's Allowed Dependencies; implementation cannot begin until it lands |

---

## Parallelization Notes

Carried forward for task generation. Four groups, with dependencies:

1. **Pure domain** — key types, name validation, public key parsing, discovery pairing, rename and delete plans. No dependency on any port; fully parallel internally; blocks everything else.
2. **Ports and adapters** — `SSHKeyWriting`, `SSHKeyGenerating`, `ClipboardWriting` plus their fakes. Parallel with each other once group 1's types exist.
3. **Models** — list model, form model, route. Depends on groups 1 and 2.
4. **Views and showcase removal** — depends on group 3 **and** on the `design-system` spec shipping.

---

## Gaps Requiring Investigation During Implementation

- Draining `Process` pipes without deadlock under Swift 6 concurrency: the shape is known, the exact `AsyncSequence` versus `readabilityHandler` choice is not.
- Whether `ScrollView` inside the fixed-height panel still exhibits the forum's collapse when the container height is exact rather than bounded. Verify on the first list implementation, before the form is built.
- The exact fixed panel height, which cannot be chosen until the design system's row metrics exist.
