# Implementation Gap Analysis

- **Feature**: `design-system`
- **Discovery Scope**: New Feature (new layer over a shipped foundation) — brownfield
- **Baseline verified**: `xcodebuild … test` passes, 68 tests in 8 suites, working tree clean
- **Analysis date**: 2026-09-30

## Summary of Key Findings

1. **New production files do not join the app target automatically.** AGENTS.md and the
   foundation spec's `research.md` both state that they do. That was true before the test
   target existed; it is false now, and it was verified empirically (see Finding 1). A spec
   that adds ~20 files must add ~20 entries to `project.pbxproj`, which AGENTS.md discourages
   doing by hand.
2. **Generated asset colour symbols are invisible to the test target.** Requirement 2.3
   (colours as named colour sets) and the test target's compilation of production sources are
   in direct conflict unless asset-symbol references are isolated to files the test target
   does not compile (Finding 2).
3. **Generated symbol names strip a trailing "Color"**: a colour set named `ProbeColor`
   produces the symbol `.probe`. This silently affects every colour token name (Finding 3).
4. **The existing `SSHDirectoryStatus` is the pattern Requirements 7.2 and 13.1 describe** —
   a closed enum with tested projections and no view involvement. The design system should
   copy it rather than invent a new shape (Finding 4).
5. **Three UI behaviours carry real uncertainty** inside a `MenuBarExtra(.window)` panel under
   `LSUIElement`: confirmation presentation (R3.8), `List` inside a bounded scroll region
   (R6.7, R14.4), and redaction versus accessibility (R10.7). These are flagged as Research
   Needed rather than resolved here.

---

## 1. Current State Investigation

### Layout and layers

The shipped foundation is 12 production files across four layers plus the composition root,
and 11 test files including three doubles in `Support/`. The dependency direction
`Types → FileAccess → Resolution → MenuBar → OpenSSHGUIApp` is enforced by directory, not by
module: the app is a single target and the test target compiles the production sources
directly, so there is no `@testable import` anywhere.

### Conventions extracted

| Convention | Evidence | Bearing on this spec |
|---|---|---|
| One primary type per file, file named after it | every file under `open-ssh-gui/` | ~20 new production files, ~15 new test files |
| Closed enums with tested projections, not view logic | `SSHDirectoryStatus.displayPath`, `.isReachable`, `.failureReason` | the shape R7.2 and R13.1 ask for already exists |
| `Sendable, Equatable` on value types | `SSHDirectoryStatus: Sendable, Equatable` | explicit `Sendable` keeps a type nonisolated under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` |
| Test naming: `@Suite`/`@Test` with sentence display strings | all 8 suites | design system suites follow suit |
| Projections tested without rendering | `SSHDirectoryStatusTests` asserts on the enum, never on a view | exactly the R13.2 mechanism |
| No previews anywhere | `grep '#Preview'` → none, though `ENABLE_PREVIEWS = YES` | R13.6 introduces the first previews in the project |

### Build settings that constrain the design

```
SWIFT_VERSION = 5.0                                  # isolation mismatches are warnings
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor            # every type is @MainActor by default
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES # every file needs its own imports
MACOSX_DEPLOYMENT_TARGET = 27.0                      # @Entry, LabeledContentStyle all available
ENABLE_PREVIEWS = YES
ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES
INFOPLIST_KEY_LSUIElement = YES                      # no Dock icon, no window to attach to
```

### Integration surfaces

- `OpenSSHGUIApp.swift` — the only place a style can be applied once for the whole app
  (Requirements 3.2, 4.3). It is excluded from the test target.
- `SSHDirectoryStatusView.swift` — the only existing view, and the only current consumer.
  Holds the `@ScaledMetric` reserved-height workaround from `c38363c`.
- `Assets.xcassets` — contains only `Contents.json`; `0a26f94` removed the template accent
  colour. Compiled into the app target only.
- `.kiro/specs/crud-ssh-keys/` now exists as a sibling spec, and will be the design system's
  first real consumer. Nothing in this analysis depends on its content.

---

## 2. Verified Findings

### Finding 1 — New files do not join the app target (Constraint, High)

`project.pbxproj` uses `objectVersion = 90`. Both `Sources` build phases are **empty**, and
only the **test** target declares `fileSystemSynchronizedGroups`, listing both root groups.
The app target declares none. Membership therefore comes entirely from two
`PBXFileSystemSynchronizedBuildFileExceptionSet` objects, and they read in opposite
directions:

| Exception set | Target | Lists | Effective meaning |
|---|---|---|---|
| `14E63CA5…` | `open-ssh-gui` | all 12 production files + `Assets.xcassets` | **inclusions** (the group is not in this target's synchronized groups) |
| `14E63CA6…` | `open-ssh-guiTests` | `Assets.xcassets`, `OpenSSHGUIApp.swift` | **exclusions** (the group is in this target's synchronized groups) |

**Verification.** A file `open-ssh-gui/DesignSystem/GapProbe.swift` containing a deliberate
type error was written to disk, then each target was built:

```
xcodebuild -target open-ssh-gui      → ** BUILD SUCCEEDED **   (file not compiled)
xcodebuild -target open-ssh-guiTests → ** BUILD FAILED **
    GapProbe.swift:1:41: error: cannot convert value of type 'String' to specified type 'Int'
```

The test target's compile line confirms it compiles all production sources plus the probe.

**Implications.**
- Every new Design System file needs an entry in the app target's `membershipExceptions`.
  At ~20 files that is ~20 hand-edited lines in `project.pbxproj`.
- The failure mode is at least loud, not silent: a file absent from the app target breaks
  compilation of `OpenSSHGUIApp.swift` the moment it references the showcase. But a
  *token or style file* never referenced from the app target would silently ship unused.
- **AGENTS.md's "New source files under `open-ssh-gui/` join the app target automatically —
  there are no per-file references to maintain" is now incorrect**, as is the same claim in
  `macos-menu-bar-foundation/research.md`. Correcting AGENTS.md is a steering-level change
  that this spec should either make or explicitly hand off.

### Finding 2 — Asset colour symbols break the test build (Constraint, High)

A colour set was added to `Assets.xcassets` and referenced from `SSHDirectoryStatusView.swift`,
a file compiled into **both** targets:

```
xcodebuild -target open-ssh-gui      → ** BUILD SUCCEEDED **
xcodebuild -target open-ssh-guiTests → ** BUILD FAILED **
    SSHDirectoryStatusView.swift:85:34: error: type 'Color' has no member 'probe'
```

`actool` runs for the app target with `--generate-swift-asset-symbols` and produces
`Assets.car` plus `GeneratedAssetSymbols.swift`. The test target's `DerivedSources` contains
no such file, because `Assets.xcassets` is excluded from it.

**Implication.** Requirement 2.3 is satisfiable, but **no production file that the test target
compiles may reference a generated asset symbol.** Options:

- **(a) Isolate the mapping.** Colour *roles* are pure values in test-visible files; exactly
  one file maps role → `Color` using generated symbols, and that file is excluded from the
  test target. Tests assert on roles, never on `Color`. This is what Requirements 13.1 and
  13.2 already describe, so it costs nothing extra and is the recommended route.
- **(b) Add `Assets.xcassets` to the test target.** One-line pbxproj change; makes the test
  bundle carry the catalog and lets tests assert on `Color` values, which they should not.
- **(c) String-based lookup** (`Color("FieldBorder", bundle: .main)`). Compiles everywhere,
  loses compile-time safety, resolves to a fallback colour under test. Not recommended.

### Finding 3 — Generated symbol names strip a trailing "Color" (Constraint, Low)

`GeneratedAssetSymbols-Index.plist` for a colour set named `ProbeColor`:

```
"relativePath" => "./ProbeColor.colorset"
"swiftSymbol"  => "probe"
"objcSymbol"   => "ACColorNameProbeColor"
```

Naming a colour set `BorderColor` yields `.border`, not `.borderColor`. The design must fix a
colour-set naming convention up front so token call sites are predictable, and Requirement
2.3's asset names should be chosen with the stripping in mind.

### Finding 4 — The precedent for R7.2 and R13.1 already exists (Asset, reuse)

`SSHDirectoryStatus` is a closed `Sendable, Equatable` enum whose `displayPath`,
`isReachable` and `failureReason` projections are unit-tested with no view involved. It is
exactly the pattern Requirement 13.1 mandates.

One observation for the design: that enum exposes its three-way state as
`isReachable: Bool` + `failureReason: String?`, a shape that can express
"reachable *and* failing" even though the enum cannot. Requirement 7.2 asks the design
system's own state type to be a closed set over success / warning / failure / in-progress, so
the cleaner arrangement is a design-system state enum plus a tested mapping from
`SSHDirectoryStatus` to it, keeping the leak out of the new layer.

### Finding 5 — The panel's layout workaround is inherited (Constraint, Medium)

`SSHDirectoryStatusView` reserves a worst-case height via
`@ScaledMetric(relativeTo: .body) private var reservedStatusHeight: CGFloat = 70`, because
`menuBarExtraStyle(.window)` hosts the view in a self-sizing panel and a height change during
layout produced `_NSDetectedLayoutRecursion` (fixed in `c38363c`).

Requirements 5.7, 14.4 and 14.5 inherit this directly: the showcase's `ScrollView` must be
given an explicit bounded height rather than sizing to content, and the composite field's
reserved validation-message space exists for the same reason.

### Finding 6 — The empty asset catalog helps R12.3 (Asset)

`0a26f94` removed the template `AccentColor`. With no accent colour asset, SwiftUI's
`.tint`/`.accentColor` follows the user's system accent, which is what Requirement 12.3 asks
for. Re-adding an `AccentColor` asset would break that requirement.

---

## 3. Requirement-to-Asset Map

| Req | Existing asset to build on | Gap | Tag |
|---|---|---|---|
| 1 Layer boundaries | four-layer directory convention; `structure.md` dependency chain | `DesignSystem/` does not exist; `structure.md`'s chain has no place for it; app-target membership per Finding 1 | Missing + Constraint |
| 2 Tokens | `Assets.xcassets` (empty), asset symbol generation on | no token types; Findings 2 and 3 shape colour tokens; no `EnvironmentValues` extension exists | Missing + Constraint |
| 3 Buttons | the Quit `Button` in `SSHDirectoryStatusView` | no styles; R3.8 confirmation presentation inside a `MenuBarExtra` panel unproven | Missing + Unknown |
| 4 Labels | `Label` + `.foregroundStyle` used inline in the indicator | no `LabelStyle`/`LabeledContentStyle`; no `LabeledContent` use yet | Missing |
| 5 Text input | none — the app has no editable field | `TextFieldStyle` unimplementable (stated in requirements); R5.7 reserved height per Finding 5 | Missing + Constraint |
| 6 Lists | none — the app renders no collection | `ListStyle` unimplementable; `List` inside a bounded scroll region in a panel unproven | Missing + Unknown |
| 7 Status + code text | `SSHDirectoryStatus` enum; the monospaced `path` and `indicator` views to extract | components do not exist; R7.6 requires rewiring the existing view | Missing (extraction, low risk) |
| 8 Empty state + header | `Text(…).font(.headline)` as an ad-hoc header | components do not exist | Missing |
| 9 Toggle + choice | none | speculative per requirements' own Boundary Context; `PickerStyle` unimplementable | Missing |
| 10 Secret field | the `~/.ssh` handling rules in `product.md`/AGENTS.md | component does not exist; R10.7 redaction-versus-accessibility unproven | Missing + Unknown |
| 11 Driven contract | `SSHDirectoryStatusView` already holds no logic and takes an injected model | no `@Binding` or closure-driven component exists yet to set the precedent | Missing (convention) |
| 12 Adaptive appearance | empty catalog favours system accent (Finding 6); `@ScaledMetric` precedent | no contrast/appearance verification anywhere; no automated way to assert it | Missing + Unknown |
| 13 Testability | `SSHDirectoryStatusTests` is the exact pattern; 68 tests green; no host app | Finding 2 constrains what tests may reference; previews in production files are compiled into the test target and need verifying | Constraint + Unknown |
| 14 Showcase | `MenuBarExtra` + `.menuBarExtraStyle(.window)`, fixed 320pt panel | showcase does not exist; Finding 5 governs its scroll region; Finding 1 governs its target membership | Missing + Constraint |

---

## 4. Implementation Approach Options

### Option A — Extend the existing `MenuBar/` layer

Put styles, tokens and composites into `open-ssh-gui/MenuBar/` alongside the status view.

- ✅ No new layer, no `structure.md` change, no new position in the dependency chain.
- ✅ Files are already covered by the existing membership pattern, though each still needs its
  own `membershipExceptions` entry (Finding 1 applies regardless of directory).
- ❌ **Violates Requirement 1.1**, which asks for a directory distinct from `MenuBar/`.
- ❌ Collapses presentation and design system into one directory, so the "no project
  dependencies" guarantee of Requirement 1.2 becomes unenforceable by inspection — the whole
  point of the layered layout is that a wrong-direction reference is visible as a
  cross-directory one.
- ❌ ~20 new files in a directory that currently holds three.

**Verdict**: rejected. It contradicts an approved requirement and dissolves the structural
guarantee the project's layering exists to provide.

### Option B — New `DesignSystem/` layer, built in one pass

A single new directory holding tokens, styles, composites and the showcase.

- ✅ Satisfies Requirement 1 directly.
- ✅ Dependency direction becomes trivially checkable: `DesignSystem/` importing anything from
  `Types/`, `FileAccess/` or `Resolution/` is a visible violation.
- ❌ The showcase is temporary and the rest is permanent; one directory mixes the two, making
  Requirement 14.8 ("deletable without editing any Design System file") harder to honour.
- ❌ ~35 new files (production + tests) landing together, with the pbxproj membership problem
  hitting all at once and no early verification that the membership approach works.

### Option C — New `DesignSystem/` layer + separate showcase directory, phased (recommended)

Structurally Option B, with two refinements:

1. **The showcase lives in its own directory**, e.g. `open-ssh-gui/Showcase/`, so Requirement
   14.8's removal is "delete one directory plus one line in `OpenSSHGUIApp.swift`" with no
   edit to any Design System file.
2. **Phased delivery**, with the riskiest unknowns resolved first:
   - *Phase 0 — prove the plumbing.* Resolve Finding 1 (target membership) and Finding 2
     (colour isolation) with one token, one style and one test. This is the phase that must
     not be skipped: both findings are project-file problems that are cheap to fix on one
     file and expensive to fix on twenty.
   - *Phase 1 — tokens and the propagating styles.* R2, R3, R4, R9.1 — the pieces that need
     no composite view and deliver the "one place" property.
   - *Phase 2 — composites.* R5, R6, R7, R8, R9.2, R10, under the R11 contract.
   - *Phase 3 — showcase and cross-cutting verification.* R14, then R12 and R13.7.

- ✅ Requirement 14.8 becomes structural rather than a matter of discipline.
- ✅ The two High-risk findings are settled against one file before ~20 more are written.
- ✅ Each phase ends with a green `xcodebuild … test`, matching how the foundation spec was
  delivered.
- ❌ A second new directory, and `structure.md` must describe both.
- ❌ Requires a deliberate decision on the dependency chain's shape (below).

**Verdict**: recommended.

#### Dependency-chain shape to decide in design

`structure.md` currently documents one linear chain. The design system depends on nothing in
the project, so inserting it linearly (`Resolution → DesignSystem → MenuBar`) overstates its
coupling. Two candidates:

```
A)  Types → FileAccess → Resolution → MenuBar → OpenSSHGUIApp
                          DesignSystem ↗                        (a source, consumed by MenuBar)

B)  Types → FileAccess → Resolution → DesignSystem → MenuBar → OpenSSHGUIApp
```

(A) is truthful — `DesignSystem/` is a root with no project dependencies, like `Types/`.
(B) is simpler to state and still forbids every reference that matters. Either way
`structure.md` needs an edit, which is a steering change and therefore a cross-spec concern.

#### Resolving Finding 1 — three routes

- **Route 1 — add each file to `membershipExceptions`.** ~20 lines, mechanical, and AGENTS.md
  warns Xcode rewrites these blocks freely. Verified only by building.
- **Route 2 — restructure membership once** so the `open-ssh-gui` group is synchronized into
  the app target and the exception sets are inverted to exclusions. One structural change
  that restores the behaviour AGENTS.md already documents and removes the per-file cost for
  every future spec. Higher one-time risk; must be verified by building both targets and
  confirming `OpenSSHGUIApp.swift` stays out of the test target.
- **Route 3 — create files through Xcode's UI**, which maintains membership automatically.
  Not available to an agent working from the command line.

Route 2 is the better investment and is the reason Phase 0 exists; Route 1 is the fallback if
Route 2 does not verify cleanly.

---

## 5. Effort and Risk

| Area | Effort | Risk | Justification |
|---|---|---|---|
| Phase 0 — target membership + colour isolation | S | **High** | `project.pbxproj` surgery on a synchronized-group setup whose semantics are inverted per target; verifiable only by building both targets |
| Tokens and propagating styles (R2–R4, R9.1) | M | Low | `ButtonStyle`, `LabelStyle`, `LabeledContentStyle`, `ToggleStyle` are all publicly implementable and well documented |
| Composites (R5–R8, R9.2, R10) | M | Medium | no existing composite in the project to pattern-match; panel layout constraints from Finding 5 apply to each |
| Showcase in the panel (R14) | S | Medium | `ScrollView` inside a self-sizing `MenuBarExtra` panel is the exact configuration that produced `_NSDetectedLayoutRecursion` |
| Confirmation presentation (R3.8) | S | **High** | presenting a confirmation from an `LSUIElement` app's menu bar panel has no precedent in this codebase and no window to attach to |
| `List` in a bounded region (R6.7, R14.4) | S | **High** | nested scrolling inside a content-sized panel; may need a non-`List` showcase representation |
| Adaptive appearance + accessibility (R12) | M | Medium | seven criteria with no automated verification path; largely manual |
| Tests (~15 suites, R13) | M | Low | the pattern is established and the baseline is green |
| **Total** | **L (1–2 weeks)** | **Medium overall** | breadth, not depth: 14 requirements over ~35 files, with three genuinely unknown UI behaviours |

---

## 6. Research Needed (carry into design)

1. **Confirmation inside a menu bar panel (R3.8).** Does `confirmationDialog` or `alert`
   present correctly from a `MenuBarExtra(.window)` panel in an `LSUIElement` app, given
   there is no key window? If not, the fallback is an in-panel confirmation state — which
   changes the `PrimitiveButtonStyle`'s shape, since an in-panel confirmation needs somewhere
   to live between activation and confirmation without the style owning state (R11.4).
2. **`List` inside a bounded scroll region (R6.7, R14.4).** Whether a native `List` behaves
   in a fixed-height container nested in a self-sizing panel, or whether the showcase must
   demonstrate rows differently from how a real screen would use them.
3. **Redaction versus accessibility (R10.7).** Whether `.privacySensitive()` and
   `.redacted(reason: .privacy)` actually withhold the value from VoiceOver, or whether
   explicit accessibility suppression is required.
4. **`#Preview` in the test target (R13.6).** Previews live in production files, which the
   test target compiles. Confirm the macro expands cleanly there and does not inflate or
   destabilise the test bundle. Cheap to verify in Phase 0.
5. **Colour-set naming convention (Finding 3).** Fix names knowing a trailing `Color` is
   stripped, and record the convention where the next contributor will find it.
6. **Environment tokens (R2.6).** Confirm the `@Entry` macro's ergonomics under
   `SWIFT_VERSION = 5.0` with `MainActor` default isolation, and whether token containers
   should be `Sendable` values like `SSHDirectoryStatus`.

---

## 7. Recommendations for the Design Phase

**Preferred approach**: Option C — a new `DesignSystem/` layer plus a separate `Showcase/`
directory, delivered in four phases with the plumbing proved first.

**Key decisions to settle in `design.md`**:

1. Which route resolves Finding 1, and whether AGENTS.md's stale claim is corrected by this
   spec or handed off as a steering change.
2. Which colour-isolation option from Finding 2 — recommended (a), roles as pure values with
   a single app-target-only mapping file.
3. The dependency-chain shape, (A) or (B), and the matching `structure.md` edit.
4. The naming scheme, given Requirement 1.5 forbids the `SSH` prefix and Finding 3 strips a
   trailing `Color` from asset symbols.
5. Whether the design-system status state is its own enum with a tested mapping from
   `SSHDirectoryStatus` (recommended, per Finding 4) or reuses the existing enum directly.
6. Where an in-panel confirmation's transient state lives if research item 1 rules out
   `confirmationDialog`, without breaching Requirement 11.4.

**Explicitly out of scope for design**: the reveal policy behind Requirement 10 and the
OpenSSH keyword vocabulary behind Requirement 9, both already assigned to later specs by the
requirements' Boundary Context.
