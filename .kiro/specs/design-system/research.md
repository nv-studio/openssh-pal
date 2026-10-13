# Research & Design Decisions

## Summary

- **Feature**: `design-system`
- **Discovery Scope**: New Feature (a new layer over a shipped foundation) — full discovery
- **Key Findings**:
  - Every style-protocol claim in `requirements.md` was verified against the macOS 27 SDK
    interface. `ButtonStyle`, `PrimitiveButtonStyle`, `LabelStyle`, `LabeledContentStyle` and
    `ToggleStyle` declare public `makeBody(configuration:)`. `TextFieldStyle`, `ListStyle` and
    `PickerStyle` declare only underscored requirements over opaque types. The requirements'
    prohibition on conforming to the latter three is therefore correct and enforceable.
  - `ButtonStyleConfiguration` carries `role`, `label` and `isPressed` but **no `isEnabled`**.
    Requirement 3.5 must read `isEnabled` from the environment, and a documented SwiftUI defect
    means `@Environment` on the style struct itself does not track — the read must happen in a
    nested `View` inside `makeBody`.
  - The gap analysis's recommended colour strategy (isolate asset-symbol references in a file
    excluded from the test target) is **unworkable** and is superseded. Adding
    `Assets.xcassets` to the test target was verified instead.
  - One structural `project.pbxproj` change makes all future source files join both targets
    automatically, replacing the ~20 per-file entries the gap analysis anticipated. Verified.
  - `privacySensitive()` does not withhold a value from VoiceOver and has no effect in an app
    unless a `.privacy` redaction reason is applied. Requirement 10 is therefore satisfied by
    keeping the value out of the view hierarchy entirely, not by a redaction modifier.

## Research Log

### Style protocol implementability

- **Context**: Requirements 5.2, 6.2 and 9.3 forbid conforming to `TextFieldStyle`, `ListStyle`
  and `PickerStyle`. The design must confirm that prohibition is grounded rather than folklore,
  and that the protocols it *does* rely on are public.
- **Sources Consulted**: `MacOSX.sdk/…/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`
  (Xcode 27.0), read directly.
- **Findings**:

  | Protocol | Sole requirement | Implementable |
  |---|---|---|
  | `ButtonStyle` | `makeBody(configuration: ButtonStyleConfiguration) -> Body` | yes |
  | `PrimitiveButtonStyle` | `makeBody(configuration: PrimitiveButtonStyleConfiguration) -> Body` | yes |
  | `LabelStyle` | `makeBody(configuration: LabelStyleConfiguration) -> Body` | yes |
  | `LabeledContentStyle` | `makeBody(configuration: LabeledContentStyleConfiguration) -> Body` | yes |
  | `ToggleStyle` | `makeBody(configuration: ToggleStyleConfiguration) -> Body` | yes |
  | `TextFieldStyle` | `_body(configuration: TextField<Self._Label>) -> Self._Body` | **no** — underscored, `_Label = _TextFieldStyleLabel` |
  | `ListStyle` | `_makeView`/`_makeViewList` over `_ListValue<Self, SelectionValue>` | **no** — underscored only |
  | `PickerStyle` | `_makeView`/`_makeViewList` over `_PickerValue<Self, SelectionValue>` | **no** — underscored only |

  All five implementable protocols are `@MainActor @preconcurrency`, which matches the
  project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` default with no extra annotation.
- **Implications**: Requirements 3, 4 and 9.1 are satisfiable exactly as written. Requirements
  5, 6 and 9.2 need the `ViewModifier` + composite route, confirming the requirements' own
  reasoning.

### Button configuration surface and the `isEnabled` defect

- **Context**: Requirements 3.4, 3.5, 3.7 and 3.8 depend on what the style configurations
  actually expose.
- **Sources Consulted**: SDK interface as above; [Using the isEnabled environment value in iOS 14 — Daniel Saidi](https://danielsaidi.com/blog/2022/05/20/using-the-isEnabled-environment-value-in-iOS-14); [@EnvironmentObject not found in ButtonStyle — Apple Developer Forums](https://developer.apple.com/forums/thread/129343).
- **Findings**:
  - `ButtonStyleConfiguration`: `role: ButtonRole?`, `label`, `isPressed: Bool`. No `isEnabled`.
  - `PrimitiveButtonStyleConfiguration`: `role: ButtonRole?`, `label`, `trigger()`.
  - `ButtonRole` provides `.destructive`, `.cancel`, `.confirm`, `.close`.
  - A style struct is not a `View`, so `@Environment` declared on it is not reinstalled when
    the environment changes; the documented workaround is a nested private `View` inside
    `makeBody` that declares the `@Environment` property.
- **Implications**: Requirement 3.4 and 3.7 read from the configuration. Requirement 3.5 reads
  `\.isEnabled` from the environment, and the design mandates the nested-`View` shape so the
  defect cannot be reintroduced. Requirement 3.8 uses `trigger()`, which is what makes
  deferring activation possible at all.

### Compile verification of the intended shapes

- **Context**: Several design choices depend on language and macro behaviour under
  `SWIFT_VERSION = 5.0` with `MainActor` default isolation, which is unusual enough to be
  worth proving rather than assuming.
- **Method**: A throwaway `open-ssh-gui/DSProbe/DSProbe.swift` was compiled by the test target,
  then deleted.
- **Findings** — all compiled with no errors or warnings:
  - `@Entry var probeDensity: Double = 1.0` in an `EnvironmentValues` extension (Requirement 2.6).
  - `ButtonStyle` with a nested `@Environment(\.isEnabled)` `View` (Requirements 3.1, 3.5).
  - `PrimitiveButtonStyle` rebuilding a `Button(role:)` and calling `trigger()` (Requirements 3.6, 3.8).
  - `ToggleStyle` using `configuration.$isOn` (Requirement 9.1, 9.4).
  - `LabeledContentStyle` composing `configuration.label` and `configuration.content` (Requirement 4.2).
  - A `Sendable, Equatable` enum with a `switch`-based `symbolName` projection (Requirements 7.2, 13.1).
  - `#Preview` inside a production file **compiles in the test target** (Requirement 13.6),
    closing research item 4 from the gap analysis.
- **Implications**: No requirement in 2, 3, 4, 7, 9 or 13 is blocked by toolchain behaviour.

### Colour tokens and target membership — correcting the gap analysis

- **Context**: Gap-analysis Finding 2 established that generated asset colour symbols exist
  only for the target that compiles `Assets.xcassets`, and recommended isolating the
  role-to-`Color` mapping in a file excluded from the test target.
- **Findings**:
  - **That recommendation does not work.** Exclusion has to cascade: if the mapping file is
    absent from the test target, every component file that *calls* the mapping also fails to
    compile there, and the test target compiles every component file. The exclusion would have
    to spread to the whole layer.
  - Removing `Assets.xcassets` from the test target's `membershipExceptions` makes the catalog
    a member of that target. Verified: a `Color.probe` reference from a Design System file then
    compiles in **both** targets.
  - Generated symbol names strip a trailing `Color`: the colour set `ProbeColor` yields the
    symbol `probe` (`GeneratedAssetSymbols-Index.plist`: `"swiftSymbol" => "probe"`).
- **Implications**: Requirement 2.3 is satisfied with the catalog in both targets. Colour
  *roles* remain pure values for Requirements 13.1 and 13.2 — that is now a testability
  convention rather than a compile-time necessity. Colour sets must not be named with a
  trailing `Color`.

### Automatic target membership for new files

- **Context**: Gap-analysis Finding 1 established that new files do not join the app target,
  implying ~20 hand-edited `project.pbxproj` entries for this spec.
- **Method**: The project file was patched, both targets built, the full suite run, and the
  patch reverted. The patch: give the app target
  `fileSystemSynchronizedGroups = ( 14E63C8E… /* open-ssh-gui */ )`, empty the app target's
  `membershipExceptions` list, and drop `Assets.xcassets` from the test target's list.
- **Findings**:
  - A new file in a new `open-ssh-gui/DesignSystem/` directory was compiled by **both**
    targets with no per-file entry. Proven by a deliberate type error failing both builds
    rather than by a passing build, which the gap analysis showed is not evidence of inclusion.
  - `OpenSSHGUIApp.swift` remains excluded from the test target, so the composition root is
    still not compiled into the test bundle.
  - `xcodebuild … test` passed: 68 tests in 8 suites.
- **Implications**: One structural change replaces ~20 per-file entries and restores the
  behaviour AGENTS.md already documents. It is a prerequisite task, not a per-file tax.

### Presenting a confirmation from a menu bar panel

- **Context**: Requirement 3.8 requires a destructive action to be confirmed. Gap-analysis
  research item 1 flagged that an `LSUIElement` app's `MenuBarExtra` panel has no key window.
- **Sources Consulted**: [MenuBarExtra — Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra); [FB10184971: no way to open the settings window from a MenuBarExtra-only app](https://github.com/feedback-assistant/reports/issues/327); [Hands-on: building a Menu Bar experience with SwiftUI — Cindori](https://cindori.com/developer/hands-on-menu-bar); [Build a macOS menu bar utility in SwiftUI — Nil Coalescing](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/).
- **Findings**: No source confirms that `confirmationDialog` or `alert` presents reliably from
  a `.menuBarExtraStyle(.window)` panel, and there is documented precedent for `LSUIElement`
  interfering with presentation from that surface. The panel also dismisses on outside click,
  which is hostile to a modal attached to it.
- **Implications**: The design does not use `confirmationDialog`. Requirement 3.8 is satisfied
  by a two-step inline confirmation rendered by the `PrimitiveButtonStyle` itself, which never
  leaves the panel. This is also better suited to a popover-style surface than a modal sheet.

### List and scroll behaviour inside a self-sizing panel

- **Context**: Requirements 6.7, 14.4 and 14.5, against the `_NSDetectedLayoutRecursion`
  regression fixed in `c38363c`.
- **Sources Consulted**: [MenuBarExtra — Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra); [Build a macOS menu bar utility in SwiftUI — Nil Coalescing](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/); [SwiftUI Menu Bar App With a Floating Window — Fazm](https://fazm.ai/blog/swiftui-menu-bar-app-floating-window-best-practices).
- **Findings**: A `.window`-style `MenuBarExtra` panel either sizes to its content or takes an
  explicit frame; explicit sizing is the established remedy for content whose height varies.
  The existing `@ScaledMetric reservedStatusHeight` workaround is the same technique applied
  to one row pair.
- **Implications**: Every scrolling region in this feature carries an explicit, `@ScaledMetric`
  bounded height. Height is never derived from content. This is why Requirement 5.7 reserves
  the validation message's space and why Requirement 14.4 bounds the showcase's scroll region.

### Redaction versus accessibility

- **Context**: Requirements 10.2 and 10.7.
- **Sources Consulted**: [How to mark content as private using privacySensitive() — Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-mark-content-as-private-using-privacysensitive); [privacySensitive(_:) documentation mirror](https://rusutikaa.github.io/docs/developer.apple.com/documentation/swiftui/lineargradient/privacysensitive(_:).html); [Privacy redaction not working in iOS16 beta widget — Apple Developer Forums](https://developer.apple.com/forums/thread/713009).
- **Findings**:
  - `privacySensitive()` only takes effect where a `.privacy` redaction reason is present in
    the environment. Widgets set it automatically; an ordinary app does not.
  - No source establishes that privacy redaction withholds the underlying string from
    VoiceOver. The consistent advice is to add explicit accessibility suppression.
  - Redaction is a visual treatment applied to a view that still holds the value.
- **Implications**: Requirement 10.2 ("shall render no character of the value") is not
  satisfiable by a redaction modifier with any confidence. The design keeps the value out of
  the view hierarchy: the component's input is a closed type that either carries a placeholder
  length or the revealed value, so a redacted secret field has nothing to leak — to the
  screen or to assistive technologies. Requirement 10.7 then holds by construction rather
  than by modifier behaviour.

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Verdict |
|---|---|---|---|---|
| Wrapper component library | A view type per control (`PanelButton`, `PanelTextInput`) | one obvious vocabulary; every parameter explicit | only styles call sites that opt in; each wrapper must re-expose native parameters or constrain them; a plain `Button` silently escapes the system | **Rejected** — defeats Requirement 3.2's "one place a call site cannot bypass" |
| Environment-propagated styles | Conform to the public style protocols, apply once at the scene | cannot be bypassed by a future call site; native behaviour, accessibility and keyboard handling retained free | three protocols are closed, so text field, list and picker need another mechanism | **Selected** for button, label, labeled row, toggle |
| ViewModifier + composite | `ViewModifier` for chrome, composite `View` for label/validation/empty-state assembly | same single definition; works where no style protocol is open | must be applied per call site, so a preview-backed inventory is the guard | **Selected** for text field, list, picker |
| Fully custom controls | Draw from primitives, reimplement editing and focus | total visual control | reimplements marked text, undo, Services, focus and accessibility; contradicts Requirements 5.8, 6.8, 9.7, 12.6 | **Rejected** |

Boundary conclusion: `DesignSystem/` is a dependency root — it references nothing else in the
project — so it sits beside `Types/` rather than between `Resolution/` and `MenuBar/`. The
showcase is a separate directory because Requirement 14.8 requires deletion without editing any
Design System file.

## Design Decisions

### Decision: Style the native controls; compose only what has no control

- **Context**: Requirement 3.2 demands that adding behaviour to every button be one edit that
  call sites cannot bypass.
- **Alternatives Considered**: wrapper component library; environment-propagated styles.
- **Selected Approach**: conform to the open style protocols and apply them once in
  `OpenSSHGUIApp`; use `ViewModifier` plus composites only where the protocol is closed or the
  unit is an assembly of several controls.
- **Rationale**: environment propagation reaches descendants that were written without any
  knowledge of the design system. A wrapper reaches only the call sites that remembered it.
- **Trade-offs**: `TextField`, `List` and `Picker` chrome must be applied explicitly, so those
  three are the only places where a call site can forget. Previews per component state
  (Requirement 13.6) are the compensating control.
- **Follow-up**: verify propagation with a component in the showcase that applies no style of
  its own and still renders styled.

### Decision: `Assets.xcassets` joins the test target; colour roles stay pure values

- **Context**: Generated colour symbols exist only for the target compiling the catalog, and
  the test target compiles every production source.
- **Alternatives Considered**: (a) isolate the mapping in a file excluded from the test target;
  (b) add the catalog to the test target; (c) string-based `Color(_:bundle:)` lookup.
- **Selected Approach**: (b), verified. `ColorRole` remains a `Sendable` enum that tests assert
  on; the mapping to `Color` is a single extension, and no test asserts on a `Color`.
- **Rationale**: (a) cannot work, because exclusion cascades to every file that calls the
  mapping. (c) discards compile-time safety for a problem (b) removes outright.
- **Trade-offs**: the test bundle carries a small catalog, and a test *could* assert on a
  `Color`. That is a review convention, stated in Requirement 13.1's terms.
- **Follow-up**: colour sets must not be named with a trailing `Color`, which the generator
  strips.

### Decision: One structural project change instead of per-file membership entries

- **Context**: Gap-analysis Finding 1 — new files join neither target's membership by default
  under the current configuration.
- **Alternatives Considered**: per-file `membershipExceptions` entries (~20); restructure
  membership once; create files through Xcode's UI.
- **Selected Approach**: restructure once — app target gains the synchronized root group, its
  exception list empties, and the test target keeps only `OpenSSHGUIApp.swift` excluded.
- **Rationale**: verified to work, benefits every later spec, and restores the behaviour
  AGENTS.md already documents. Per-file entries are a recurring tax that Xcode may rewrite.
- **Trade-offs**: a one-time structural edit to `project.pbxproj`, which AGENTS.md asks to
  avoid. Mitigated by being verified before the rest of the feature is written.
- **Follow-up**: AGENTS.md's stale claim, and the same claim in
  `macos-menu-bar-foundation/research.md`, need correcting; `structure.md` needs the new layer.

### Decision: Inline two-step confirmation rather than `confirmationDialog`

- **Context**: Requirement 3.8, on a surface with no key window that dismisses on outside click.
- **Alternatives Considered**: `confirmationDialog`; `alert`; inline two-step; caller-owned
  confirmation state.
- **Selected Approach**: the `PrimitiveButtonStyle` withholds `trigger()` until a second
  activation, rendering a confirming appearance in between. The pending flag lives in a nested
  private `View` and its only effect is whether the caller's action runs.
- **Rationale**: no modal presentation on a surface where presentation is unverified; the
  pattern suits a popover.
- **Trade-offs**: Requirement 11.4 forbids `@State` for values meaningful outside the
  component. A pending confirmation is transient presentation state permitted by 11.5, and it
  never alters caller data — but it does gate the caller's action, so the design records this
  as a deliberate, bounded exception rather than pretending it is not state.
- **Follow-up**: if a window scene ever appears, re-evaluate a real dialog.

### Decision: A redacted secret never holds the value

- **Context**: Requirements 10.2 and 10.7, given that `privacySensitive()` is a widget-oriented
  visual treatment with no VoiceOver guarantee.
- **Alternatives Considered**: `redacted(reason: .privacy)`; `privacySensitive()`;
  a closed input type that omits the value when redacted.
- **Selected Approach**: the component's input is a closed type whose redacted case carries
  only a placeholder length. The value is absent from the view hierarchy until the caller
  reports it revealed.
- **Rationale**: makes 10.2 and 10.7 structural. Nothing can leak a value the view never received.
- **Trade-offs**: the caller holds the value and decides when to pass it, which is what
  Requirement 10.3 asks for anyway.
- **Follow-up**: the key-management spec owns the reveal policy and any audit obligation.

## Risks & Mitigations

- **Project-file restructuring goes wrong and silently drops files from a target** — verified in
  advance; the acceptance check is a deliberate compile error failing *both* builds, since a
  passing build is not evidence of inclusion.
- **Panel layout recursion returns** (`_NSDetectedLayoutRecursion`, `c38363c`) — every scrolling
  region and the validation-message slot take explicit `@ScaledMetric` heights; height is never
  content-derived.
- **`List` misbehaves inside a bounded region in the panel** — the showcase demonstrates the
  list at an explicit height; if a native `List` proves unusable there, the composite falls back
  to a `LazyVStack` of styled rows, which keeps Requirement 6.1's row chrome intact while
  Requirement 6.8's native selection and keyboard navigation would need re-examination.
- **Style propagation regressions are invisible to unit tests** — previews per component state,
  plus a showcase section that deliberately applies no local style.
- **Requirement 9 and 10 are speculative** — their input types accept caller-supplied options
  and values and encode no OpenSSH vocabulary, so the config and key specs can reshape them
  without rewriting the layer.
- **Appearance and accessibility (Requirement 12) has no automated verification** — manual
  checks recorded per criterion; the colour-role indirection at least makes "no meaning by
  colour alone" reviewable in a pure value.

## References

- [MenuBarExtra — Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra) — panel sizing and style.
- [Using the isEnabled environment value in iOS 14 — Daniel Saidi](https://danielsaidi.com/blog/2022/05/20/using-the-isEnabled-environment-value-in-iOS-14) — the nested-`View` workaround for `@Environment` in a style.
- [@EnvironmentObject not found in ButtonStyle — Apple Developer Forums](https://developer.apple.com/forums/thread/129343) — same defect class.
- [How to mark content as private using privacySensitive() — Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-mark-content-as-private-using-privacysensitive) — redaction reasons are required for the modifier to act.
- [Privacy redaction not working in iOS16 beta widget — Apple Developer Forums](https://developer.apple.com/forums/thread/713009) — reliability of privacy redaction.
- [FB10184971: no way to open the settings window from a MenuBarExtra-only app](https://github.com/feedback-assistant/reports/issues/327) — `LSUIElement` presentation limits.
- [Hands-on: building a Menu Bar experience with SwiftUI — Cindori](https://cindori.com/developer/hands-on-menu-bar) — panel behaviour.
- [Build a macOS menu bar utility in SwiftUI — Nil Coalescing](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/) — explicit frame guidance.
- [SwiftUI Menu Bar App With a Floating Window — Fazm](https://fazm.ai/blog/swiftui-menu-bar-app-floating-window-best-practices) — fixed-frame practice.
- `MacOSX.sdk/…/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface` (Xcode 27.0) — the
  authoritative source for every style-protocol claim above.
