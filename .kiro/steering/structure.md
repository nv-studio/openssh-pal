# Project Structure

## Organization Philosophy

**Layered.** Each directory under `open-ssh-gui/` is one architectural layer, so a disallowed
dependency shows up as a cross-directory reference pointing the wrong way. Layers are not
feature folders: a new feature adds types to the existing layers rather than a new vertical
slice.

The dependency direction is one-way:

```
Types → FileAccess → Resolution → MenuBar → OpenSSHGUIApp
```

A reference that runs right-to-left is an error, not a style preference.

## Directory Patterns

### Domain values and errors
**Location**: `open-ssh-gui/Types/`
**Purpose**: Value types and typed error enums with no dependencies of their own. Wrappers that
make a validated thing distinguishable from a raw one, and snapshots that make process state
injectable.
**Example**: a resolved directory wrapping a `URL` so a validated directory is not
interchangeable with any other path; a launch-environment value owning the override spellings.

### Ports and adapters
**Location**: `open-ssh-gui/FileAccess/`
**Purpose**: The protocol through which *all* file access passes, plus its concrete
implementations. The only place permitted to import `FileManager`.
**Example**: a read-only port declaring list/probe/read, and a `nonisolated` adapter whose
methods are `@concurrent`.

### Business rules
**Location**: `open-ssh-gui/Resolution/`
**Purpose**: Decisions expressed as pure logic over injected inputs. Depends on ports, never on
adapters, so every rule is testable without a file system.
**Example**: the resolver that owns the `.ssh` name, the override channels, their precedence
and the validation-failure semantics.

### Presentation
**Location**: `open-ssh-gui/MenuBar/`
**Purpose**: A closed status enum, an `@Observable` `@MainActor` model holding state, and the
SwiftUI views. Views bind to a model and contain no logic.
**Example**: a status enum in which reachable-carrying-an-error is unrepresentable, plus the
projection the view renders.

### Composition root
**Location**: `open-ssh-gui/OpenSSHGUIApp.swift`
**Purpose**: The scene topology and the single wiring point. The only place that touches
`ProcessInfo` or asks for the home directory, and the only place that constructs an adapter.
Kept short so a bypassed seam is visible in review.

### Tests and test support
**Location**: `open-ssh-guiTests/`, with doubles in `open-ssh-guiTests/Support/`
**Purpose**: One test file per production type, named after it. Shared fakes and the
scratch-directory helper live in `Support/` and are reused rather than re-invented per suite.
**Example**: an immutable in-memory port conformer; a call-counting conformer for when
invocation counts are the assertion; a scoped scratch-directory helper.

## Naming Conventions

- **Files**: one primary type per file, file named exactly after that type
  (`SSHDirectoryResolver.swift`). Test files append `Tests`.
- **Types**: `UpperCamelCase`. Protocols describing a capability read as gerunds
  (`SSHDirectoryReading`); adapters name their backing technology first
  (`FileSystemSSHDirectoryReader`, `InMemorySSHDirectoryReader`).
- **Everything else**: `lowerCamelCase`. No `_` prefixes, no Hungarian notation, no
  abbreviations that are not universal (`url`, `id`, `ssh` are fine).
- **Errors**: `<Domain>Error`, cases naming the condition and carrying the offending `URL`.
- **Tests**: `@Test` display strings are sentences stating the behaviour and, where it is not
  obvious, why it matters — they are the first thing a failure shows.

Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/);
clarity at the point of use beats brevity.

## Import Organization

There are no modules to alias — the app is one target, and the test target compiles the
production sources directly, so no `@testable import` is needed. Imports are framework-level
only:

```swift
import Foundation   // values, errors, adapters
import SwiftUI      // views and the App
import Observation  // observable models
import Testing      // test files
```

`import Foundation` in a view file, or any sign of `FileManager` outside `FileAccess/`, is a
layering violation worth rejecting.

## Code Organization Principles

**Prefer `struct` and `enum`.** Reach for a class only when identity or shared mutable state is
genuinely required — the observable model is a class because SwiftUI needs a stable reference;
almost nothing else should be.

**Prefer `let`, and default to `private`.** Widen access only when a caller outside the file
needs it.

**Narrow protocols over broad ones.** `SSHDirectoryReading` rather than an `SSHManaging` that
does everything. A component that only reads depends only on the reading port, which is what
makes the read-only guarantee structural rather than aspirational.

**One responsibility per type.** Parsing a config, representing a host entry, persisting a
change and rendering a view are four types. A view never parses.

**Extend rather than switch.** New config keywords or key types should extend the model, not
require edits to a growing `switch` in unrelated code.

**Comment the non-obvious decision, not the obvious code.** The valuable comments in this
codebase explain why an annotation is load-bearing or why a fallback is deliberately absent —
the kind of thing a future contributor would otherwise "simplify" away.

---
_Document patterns, not file trees. New files following patterns shouldn't require updates_
