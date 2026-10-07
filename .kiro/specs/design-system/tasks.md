# Implementation Plan

Tests precede implementation throughout, per `tech.md` ("Tests are written before the
implementation"). For this layer that means each token and input type's suite is written first;
styles and composites carry `#Preview`s instead, because SwiftUI offers no way to assert on
rendered output and the project takes no view-inspection dependency. No sub-task is marked
optional for that reason — the test work here *is* the coverage, not an add-on.

- [ ] 1. Foundation: target membership and layer scaffold

- [x] 1.1 Restore automatic target membership for new source files
  - Give the app target the `open-ssh-gui` synchronized root group and empty its per-file
    membership exception list, so a new source file joins the app target without a project-file
    edit; remove the asset catalog from the test target's exception list so generated colour
    symbols resolve under test
  - Confirm the composition root stays excluded from the test target, preserving the no-host
    safety control
  - Observable completion: a scratch file in a new `DesignSystem/` directory containing a
    deliberate type error fails **both** the app and test target builds; after removing the
    error both build and `xcodebuild … test` reports 68 tests in 8 suites passing. A passing
    build alone is not acceptance evidence — the current configuration compiles unknown files
    silently in the app target
  - _Requirements: 1.1, 1.7, 13.4, 13.7_

- [x] 1.2 Correct the stale target-membership guidance and record the new layer
  - Replace the claim that new files under the app source directory join the app target
    automatically; it is true only after 1.1 and was false beforehand
  - Document the design system as a dependency root alongside the domain-value layer, and the
    showcase directory as temporary, including the rule that the design system may reference
    nothing else in the project
  - Observable completion: the steering structure document names both new directories and states
    the dependency rule, and no agent-facing document still asserts automatic membership as a
    property of the synchronized group alone
  - _Requirements: 1.1, 1.2_

- [ ] 2. Core: design token layer

- [x] 2.1 (P) Spacing, radius and typography tokens
  - Define namespaced scales for spacing, corner radii and text styles, each expressed relative
    to a system text style so the user's text size is honoured
  - Write the token suites first, asserting the scales are readable without constructing a view
    and that the spacing scale is monotonic
  - Observable completion: the token suites pass, and no component written later needs a numeric
    literal for spacing, radius or font size
  - _Boundary: Spacing, Radius, Typography_
  - _Requirements: 2.1, 2.2, 2.5, 2.7, 12.4, 13.3_

- [x] 2.2 (P) Colour role vocabulary and its catalog-backed appearance
  - Define a closed, sendable set of semantic colour roles naming intents rather than hues, and a
    single mapping from role to rendered style — the only place in the codebase that references a
    generated asset colour symbol
  - Prefer a system semantic colour or material wherever one expresses the intent; add a colour
    set to the catalog only where none fits, and name sets knowing the symbol generator strips a
    trailing "Color"
  - Write the role suite first, asserting the vocabulary is complete and that distinct intents are
    distinct cases; assert on roles only, never on rendered colour values
  - Observable completion: the role suite passes in the test target, the mapping handles every
    role exhaustively, and adding a role without a matching colour fails to compile
  - _Boundary: ColorRole, ColorRoleAppearance, Assets.xcassets_
  - _Requirements: 2.3, 2.4, 12.1, 12.2, 12.3, 12.5, 13.1, 13.2_

- [x] 2.3 (P) Subtree-overridable density token
  - Expose density as an environment value so a portion of the view hierarchy can override it
    without affecting its siblings
  - Observable completion: a preview demonstrates two sibling subtrees rendering at different
    densities from one override
  - _Boundary: Density_
  - _Requirements: 2.6_

- [ ] 3. Core: closed input types

- [x] 3.1 (P) Status role and its projections
  - Define a closed, sendable status vocabulary over success, warning, failure and in-progress in
    which reachable-and-failing cannot be expressed, projecting a symbol name and a colour role
    per case
  - Write the suite first, asserting every case projects a distinct symbol as well as a distinct
    role, so no two states are separable by tint alone
  - Observable completion: the suite passes and the projections are callable without rendering
  - _Boundary: StatusRole_
  - _Depends: 2.2_
  - _Requirements: 7.2, 7.3, 11.7, 12.5, 13.1, 13.2_

- [x] 3.2 (P) Field validation state
  - Define a closed validation type carrying a message only when invalid, so "valid but carrying
    an error message" is unrepresentable
  - Write the suite first, asserting the invalid case exposes its message and the valid case
    exposes none
  - Observable completion: the suite passes, and no caller can construct a contradictory state
  - _Boundary: FieldValidation_
  - _Requirements: 5.5, 5.6, 11.7_

- [x] 3.3 (P) Secret presentation state
  - Define a closed type whose redacted case carries only a placeholder length and whose revealed
    case carries the value, so a redacted secret never holds the value at all
  - Write the suite first, asserting no accessor on the redacted case yields any character of a
    value — the property that makes redaction structural rather than a visual treatment
  - Observable completion: the suite passes, and the type offers no path from a redacted case to
    a value
  - _Boundary: SecretPresentation_
  - _Requirements: 10.1, 10.2, 10.7, 11.7_

- [x] 3.4 (P) Empty state content
  - Define the content an empty state renders: a message, an optional symbol and an optional
    action, with absence modelled rather than signalled by sentinel values
  - Observable completion: the type expresses message-only, message-with-symbol and
    message-with-action without any invalid combination
  - _Boundary: EmptyStateContent_
  - _Requirements: 8.1, 11.7_

- [ ] 4. Core: propagating styles and chrome

- [x] 4.1 (P) Button appearance style
  - Conform to the button style protocol so appearance is inherited by every descendant button
    rather than applied per call site; provide prominent and plain variants distinguished by more
    than colour
  - Drive the pressed appearance from the configuration's pressed flag and the destructive
    appearance from its role; read the enabled flag **from the environment inside a nested private
    view**, because the configuration carries no enabled state and a style struct is not a view,
    so an environment property declared on the style itself silently always reports enabled
  - Keep the native button, so keyboard activation, focus ring and accessibility are unmodified
  - Observable completion: previews show resting, pressed, disabled, prominent, plain and
    destructive appearances, and the disabled preview visibly differs — proving the nested-view
    read works
  - _Boundary: PanelButtonStyle_
  - _Requirements: 3.1, 3.3, 3.4, 3.5, 3.7, 3.9, 11.4, 12.5_

- [x] 4.2 (P) Confirming activation style
  - Conform to the primitive button style protocol, which exposes the trigger the appearance-only
    protocol does not, so activation can be withheld in one place for every button it is applied to
  - For a destructive role, require a second activation before invoking the caller's action,
    rendering a confirming appearance in between; trigger other roles immediately
  - Present no modal: the panel has no key window and dismisses on outside click, and dialog
    presentation from that surface is unverified
  - Confine the pending flag to a nested private view whose only effect is whether the caller's
    closure runs; it never alters caller data and is discarded when the panel closes
  - Observable completion: a preview shows a destructive button requiring two activations and a
    non-destructive one requiring a single activation; dismissing returns it to rest
  - _Boundary: ConfirmingButtonStyle_
  - _Requirements: 3.6, 3.8, 11.5_

- [x] 4.3 (P) Label and labeled-row styles
  - Conform to the label and labeled-content style protocols so both are inherited by descendants;
    provide primary and secondary emphasis variants
  - Bound label text to a limited number of lines and truncate rather than widening the panel
  - Keep label text available to assistive technologies as a single element
  - Observable completion: previews show both emphases and a label whose text exceeds the panel
    width truncating within its line bound instead of expanding the layout
  - _Boundary: PanelLabelStyle, PanelRowStyle_
  - _Requirements: 4.1, 4.2, 4.4, 4.5, 4.6_

- [x] 4.4 (P) Toggle style
  - Conform to the toggle style protocol, taking the value as a caller-owned binding and
    preserving native keyboard activation and accessibility
  - Observable completion: a preview shows on and off states driven by a binding the preview owns
  - _Boundary: PanelToggleStyle_
  - _Requirements: 9.1, 9.4, 9.7_

- [x] 4.5 (P) Field and row chrome
  - Provide field and row chrome as view modifiers, because the text field and list style
    protocols declare only underscored requirements over opaque types and cannot be implemented
    without calling private SDK interface
  - Conform no type to either protocol, so a future contributor cannot reintroduce the private
    dependency by following an existing example
  - Observable completion: a native text field and a native list row both render project chrome
    through the modifiers, and the layer contains no conformance to either closed protocol
  - _Boundary: FieldChrome, RowChrome_
  - _Requirements: 5.1, 5.2, 6.1, 6.2_

- [ ] 5. Core: composite components

- [x] 5.1 (P) Empty state and section header
  - Render a caller-supplied message with optional symbol and optional action, the action drawn
    through the button style so an empty state's affordance matches every other button
  - Provide a grouping header that uses the typography tokens and is exposed to assistive
    technologies as a heading
  - Observable completion: previews cover message-only, with-symbol and with-action empty states
    plus a header, all laying out within the panel width without horizontal scrolling
  - _Boundary: EmptyState, SectionHeader_
  - _Depends: 3.4_
  - _Requirements: 8.2, 8.3, 8.4, 8.5, 8.6, 13.6_

- [x] 5.2 (P) Status indicator and code text
  - Render a status as icon, message and role tint, deriving content solely from caller input
  - Render monospaced text the user can select and copy, truncating in the middle when it cannot
    fit so both ends of a path stay visible
  - Observable completion: previews cover all four status cases and a path long enough to
    truncate, with its leading and trailing segments both still legible
  - _Boundary: StatusIndicator, CodeText_
  - _Depends: 3.1_
  - _Requirements: 7.1, 7.4, 7.5, 7.7, 13.6_

- [x] 5.3 (P) Labeled field
  - Compose a label, a native text field carrying the field chrome, and a validation message as
    one unit; take the text as a caller-owned binding and the validation state as caller input,
    deciding validity nowhere
  - Reserve the validation message's height when valid, so showing a message never changes the
    component's height — the panel sizes to its content and a height change during layout is what
    produced the layout recursion this project already fixed once
  - Accept focus as a binding where a caller needs to drive it, and associate label with field
    for assistive technologies
  - Observable completion: previews cover valid, invalid and long-message states, and the
    component's height is identical across all three
  - _Boundary: LabeledField_
  - _Depends: 3.2, 4.5_
  - _Requirements: 5.3, 5.4, 5.7, 5.8, 5.9, 5.10, 11.1, 11.2, 11.3, 13.6_

- [x] 5.4 (P) Enumerated choice row
  - Build an enumerated-choice row on the native picker, since the picker style protocol declares
    no public requirement; take the value as a caller-owned binding
  - Accept options as a caller-supplied collection and enumerate no OpenSSH keyword or value, so
    the configuration spec supplies the vocabulary and can reshape it without touching this layer
  - Observable completion: a preview renders exactly the options the preview supplies and no
    others, with selection driven by a binding the preview owns
  - _Boundary: ChoiceRow_
  - _Requirements: 9.2, 9.3, 9.5, 9.6, 13.6_

- [x] 5.5 Bounded list with empty state
  - Render a caller-supplied collection with caller-supplied row content and caller-owned
    selection, requiring the caller to supply each row's stable identity
  - Render the empty state when the collection is empty, rather than an empty rows area
  - Scroll within an explicit bounded height rather than growing the panel; height is never
    derived from content
  - Wrap the native list so row selection, keyboard navigation and accessibility are preserved.
    If a native list proves unusable inside a bounded region in the panel, fall back to a stack of
    chrome-carrying rows and record the lost native selection and keyboard navigation as a
    deviation from requirement 6.8 rather than claiming coverage
  - Observable completion: previews cover empty, single-row and overflowing collections, and the
    overflowing case scrolls inside a panel whose size does not change
  - _Boundary: BoundedList_
  - _Depends: 5.1, 4.5_
  - _Requirements: 6.3, 6.4, 6.5, 6.6, 6.7, 6.8, 13.6_

- [x] 5.6 Secret field
  - Report a reveal request to the caller and reveal nothing on the component's own authority;
    render the value only while the caller reports it revealed
  - Copy, log and persist nothing, and read no file — the component renders only what it is given
  - Describe the field, not its contents, to assistive technologies while redacted; use no privacy
    redaction modifier, which requires a redaction reason an app does not set and does not withhold
    the string from assistive technologies
  - Observable completion: previews cover redacted and revealed presentations; the redacted
    preview contains no character of a value anywhere in its view hierarchy
  - _Boundary: SecretField_
  - _Depends: 3.3, 5.2_
  - _Requirements: 10.3, 10.4, 10.5, 10.6, 13.6_

- [ ] 6. Integration

- [x] 6.1 Apply the styles once at the panel root
  - Apply the button, label, labeled-row and toggle styles at the scene's root so every descendant
    inherits them, which is what makes the appearance impossible for a later call site to bypass
  - Observable completion: a plain button written with no style modifier of its own renders the
    project appearance, demonstrated by a showcase section that applies nothing locally
  - _Requirements: 1.4, 3.2, 4.3_

- [x] 6.2 Rewire the SSH directory status view onto the components
  - Add a projection from the existing directory status to the design system's status vocabulary,
    keeping the mapping in the presentation layer so the design system never imports an SSH type
  - Render the resolved path through the code text component and the reachability row through the
    status indicator, removing the hand-built rows and the inline reserved-height workaround now
    that the components own that concern
  - Write the mapping suite first, covering every directory status case exhaustively
  - Observable completion: the mapping suite passes, the view declares no font, spacing or colour
    value of its own, and it presents the same information it presented before
  - _Requirements: 1.4, 7.6_

- [x] 6.3 Build the temporary showcase sections
  - Render every component in every state its input types can express, one section per component
    headed by the section header so the showcase exercises that component too
  - Drive everything from values the showcase declares itself; read nothing from the SSH directory
  - Include one section that applies no local style, as the standing check that style propagation
    from the scene root still works
  - Keep the showcase in its own directory and mark its source as temporary, naming the next
    feature spec as its remover
  - Observable completion: every component and every input case appears in the panel, and deleting
    the showcase directory plus one line in the composition root removes it with no edit to any
    design system file
  - _Requirements: 14.1, 14.2, 14.3, 14.6, 14.7, 14.8, 14.9_

- [x] 6.4 Present the showcase in the panel within a bounded scroll region
  - Present the showcase as the panel's content with the Quit control outside the scrolling region,
    so the user's only way to quit an agent-mode app is never scrolled away
  - Give the scrolling region an explicit scaled height so the panel is one fixed size and its
    content changing does not resize it
  - Keep the menu bar scene the only scene
  - Observable completion: opening the panel logs no AppKit layout recursion, the panel's size is
    unchanged as showcase content settles, and Quit remains reachable without scrolling
  - _Requirements: 14.4, 14.5, 14.10_

- [ ] 7. Validation

- [x] 7.1 Audit the driven-component contract across the layer
  - Confirm every component receives displayed values from its caller, exposes two-way values as
    caller-owned bindings and actions as caller-supplied closures, and declares no state for any
    value meaningful outside it
  - Confirm no component constructs or holds an observable model, a port conformer or any
    application service
  - Record the confirming activation style's pending flag as the single intended exception, with
    its justification, so a reviewer can accept or reject it deliberately rather than discovering it
  - Observable completion: every component conforms or is listed as an explicit, justified
    exception; the list contains exactly one entry
  - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7_

- [ ] 7.2 Verify adaptive appearance and accessibility against the showcase
  - Check light and dark appearance, increased contrast, a changed system accent, and a changed
    text size, including that spacing dependent on text size scales with it
  - Check every state remains distinguishable with colour disregarded, that every control and
    non-decorative image carries an accessibility label, and that a redacted secret exposes no
    value to assistive technologies
  - Check legibility over the menu bar panel's material
  - Observable completion: each of the seven criteria is confirmed against the showcase, and any
    failure is fixed in the token or component that owns it rather than at a call site
  - **Status: partially verified, left open deliberately.** Statically confirmed: each colour set
    carries base, dark, high-contrast and dark-high-contrast variants (12.1, 12.2); no accent asset
    exists and prominence resolves to the system tint (12.3); every typography token derives from a
    system text style and every variable height is a scaled metric (12.4); status roles are proven
    distinct by icon as well as tint in `StatusRoleTests`, and button emphases differ by fill and
    weight (12.5, in part); accessibility labels, heading traits, combined elements and hidden
    decoration are present on every component that needs them (12.6)
  - **Still requires a human looking at the screen**: that the rendered result is legible in both
    appearances and at increased contrast (12.1, 12.2), that it remains legible over the menu bar
    panel's material (12.7), and that the states are genuinely separable with colour disregarded
    rather than merely differently named (12.5). None of this is assertable from a test, and the
    panel cannot be opened without clicking the menu bar item
  - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 12.7_

- [x] 7.3 Confirm the layer's boundaries and the green build
  - Confirm the design system references no type from the domain-value, file-access or resolution
    layers and no file-system or process API, that its type names avoid the prefix reserved for
    OpenSSH domain concepts, and that its tokens are reachable only through namespaced containers
  - Confirm no test names the user's home directory or a literal SSH directory path, and that the
    test target still has no host application
  - Observable completion: the full suite passes for a macOS destination with the new suites
    included, and the layer's only imports are Apple SDK frameworks
  - _Requirements: 1.2, 1.3, 1.5, 1.6, 13.4, 13.5, 13.7_
