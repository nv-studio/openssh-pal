# Requirements Document

## Project Description (Input)
add-design-system

Implement the project's atomic design system components — text input, button, list and
label — plus the additional base components this app's roadmap needs, following Swift and
SwiftUI best practice. Components are **driven, not stateful**: they receive everything they
display from their caller and own no source of truth. Behaviour that applies to a whole
class of component must be changeable in one place.

On completion the app shows a **temporary** showcase UI demonstrating every component, which
the next feature spec removes.

## Introduction

This spec adds a Design System layer to open-ssh-gui: a set of design tokens and component
abstractions that every later feature builds its UI from, so that a visual or behavioural
change to a class of control is one edit rather than a search across views.

The layer's central decision is to **style the native controls rather than replace them**.
SwiftUI's style protocols (`ButtonStyle`, `PrimitiveButtonStyle`, `LabelStyle`,
`LabeledContentStyle`, `ToggleStyle`) are applied once to an ancestor view and propagate
through the environment to every descendant control. That is what delivers the "one place"
requirement in a way that cannot be bypassed: a `Button` written by a future contributor who
never read the design-system docs still picks up the project's appearance and behaviour,
because the native control *is* the entry point. A wrapper view — `SSHButton` — would only
style the call sites that remembered to use it.

Three of SwiftUI's style protocols are closed: `TextFieldStyle`'s only requirement is the
underscored `_body(configuration:)` over an opaque configuration type, and `ListStyle` and
`PickerStyle` declare no public requirement at all. For those controls the equivalent
single-definition mechanism is a `ViewModifier` plus a composite view, and this spec forbids
conforming to the closed protocols rather than reaching for underscored API that an SDK
update can break.

Standalone view types are reserved for **compositions** — a field with its label and
validation message, a list with its empty state — where there is no native control to style.
The rule throughout is: style the controls, compose the layouts.

## Boundary Context

- **In scope**: a self-contained Design System layer depending on nothing in the project; a
  token layer for spacing, radii, typography and colour; button, label, text input and list
  components; status indicator and monospaced code text; empty state and section header;
  toggle and enumerated-choice row; a redacted secret field; the driven-component contract;
  adaptive appearance and accessibility; unit-testable appearance decisions; and a temporary
  in-panel showcase.

- **Out of scope**: parsing `~/.ssh/config` or honouring `Include`; host entry create, edit
  and delete; key pair listing, generation and deletion; any file writing, and therefore the
  atomic-write, permission and backup rules; the reveal *policy* for key material; a
  user-facing theme or appearance setting; a window scene; any third-party dependency; and
  the bundle identifier, signing and notarization still deferred by the foundation spec.

- **Adjacent expectations**:
  - `MenuBarExtra` remains the only scene. The showcase lives inside the existing panel, at
    its real 320pt width, so components are demonstrated at the width they will ship at.
  - The SSH directory status view is refactored onto these components but the panel presents
    the showcase in its place for the duration of this spec. The next feature spec removes
    the showcase and decides what the panel presents instead.
  - **Requirement 9 (toggle and enumerated choice) is speculative.** Nothing parses
    `~/.ssh/config` yet, so the shape of a config-value editor is a guess. Requirement 9.5
    contains the risk by forbidding the component from enumerating any OpenSSH keyword or
    value itself; the config spec supplies those and may reshape the component.
  - **Requirement 10 (secret field) ships the control, not the policy.** The key-management
    spec owns the reveal flow, what constitutes key material, and any audit obligation.
    Requirement 10.3 keeps that authority with the caller so this control cannot pre-empt it.
  - Later specs adopt these components rather than styling controls inline; a feature that
    needs a value no token defines adds a token.

## Requirements

### Requirement 1: Design System Layer Boundaries
**Objective:** As a developer, I want the design system to be a self-contained layer, so that
components can never reach SSH logic or the file system and every later feature can adopt
them without creating a dependency cycle.

#### Acceptance Criteria
1. The Design System layer shall reside in a single directory under `open-ssh-gui/`, distinct from `Types/`, `FileAccess/`, `Resolution/` and `MenuBar/`.
2. The Design System layer shall depend only on Apple SDK frameworks, and shall not reference any type declared in `Types/`, `FileAccess/` or `Resolution/`.
3. The Design System layer shall not reference `FileManager`, `ProcessInfo`, or any other file-system or process API.
4. When a view in `MenuBar/` renders a control, the MenuBar layer shall obtain that control's appearance from the Design System layer rather than declaring font, spacing, radius or colour values inline.
5. The Design System layer shall not prefix its type names with `SSH`, which is reserved for types modelling OpenSSH domain concepts.
6. The Design System layer shall expose its tokens through namespaced containers rather than as top-level constants.
7. The open-ssh-gui project shall build for a macOS destination with the Design System layer present.

### Requirement 2: Design Token Layer
**Objective:** As a developer, I want every spacing, typography and colour decision to have
exactly one definition, so that a visual change is a one-line edit rather than a search
across views.

#### Acceptance Criteria
1. The Design System shall define named tokens for spacing, corner radii and typography.
2. The Design System's components shall not contain a numeric literal for spacing, radius or font size outside the token definitions.
3. The Design System shall define its colours as named colour sets in the asset catalog rather than as in-code component values.
4. Where a system semantic colour or material expresses the intent, the Design System shall use it rather than defining a fixed colour of its own.
5. The Design System shall express typography relative to a system text style, so that the user's chosen text size is honoured.
6. Where a token must vary for part of the view hierarchy, the Design System shall expose it as an environment value that a subtree can override.
7. When a component requires a value that no token defines, the Design System shall require a new token rather than a literal at the call site.

### Requirement 3: Button Components
**Objective:** As a developer, I want button appearance and activation behaviour defined
once, so that adding behaviour to every button in the app is a single edit that a future
call site cannot bypass.

#### Acceptance Criteria
1. The Design System shall provide button appearance as a `ButtonStyle` conformance applied to SwiftUI's native `Button`, and shall not provide a replacement button view for the standard case.
2. When a Design System button style is applied to an ancestor view, the Design System shall apply that appearance to every descendant `Button` without any change at those call sites.
3. The Design System shall provide at least a prominent and a plain button appearance.
4. While a button is pressed, the Design System shall render a pressed appearance distinct from its resting appearance.
5. While a button is disabled, the Design System shall render a disabled appearance distinct from its resting appearance, and shall not invoke the button's action.
6. The Design System shall provide a `PrimitiveButtonStyle` conformance that intercepts activation, so that behaviour applying to every button can be added in one place.
7. When a button declares the destructive role, the Design System shall render a destructive appearance.
8. When a destructive-role button is activated through the Design System's confirming button style, the Design System shall invoke the button's action only after the user confirms.
9. The Design System's button components shall preserve the native `Button`'s keyboard activation, focus ring and accessibility behaviour.

### Requirement 4: Label and Labeled Row Components
**Objective:** As a developer, I want labels and key/value rows to come from one definition,
so that text emphasis and row layout stay consistent across every panel the app grows.

#### Acceptance Criteria
1. The Design System shall provide label appearance as a `LabelStyle` conformance applied to SwiftUI's native `Label`.
2. The Design System shall provide key/value row appearance as a `LabeledContentStyle` conformance applied to SwiftUI's native `LabeledContent`.
3. When a Design System label style is applied to an ancestor view, the Design System shall apply it to every descendant `Label` without any change at those call sites.
4. The Design System shall provide label variants for at least a primary and a secondary emphasis.
5. If a label's text cannot fit the panel's width, then the Design System shall truncate it within a bounded number of lines rather than widening the panel.
6. The Design System's label components shall present their text to assistive technologies as a single accessible element.

### Requirement 5: Text Input Components
**Objective:** As a developer, I want text fields styled in one place and composed with their
label and validation message, so that every field in the app looks and behaves alike while
the caller keeps ownership of the text.

#### Acceptance Criteria
1. The Design System shall provide text field appearance as a `ViewModifier` applied to SwiftUI's native `TextField`.
2. The Design System shall not conform any type to `TextFieldStyle`, whose only requirement is underscored SDK API.
3. The Design System shall provide a composite field component presenting a label, the text field and a validation message as one unit.
4. The composite field component shall take the edited text as a `Binding` owned by its caller.
5. The composite field component shall take its validation state as a caller-supplied value, and shall not decide validity itself.
6. When the caller reports an invalid validation state, the composite field component shall display the accompanying message together with an invalid appearance.
7. While the caller reports no validation problem, the composite field component shall reserve the space its validation message would occupy, so that showing a message does not change the component's height.
8. The Design System's text input components shall preserve the native `TextField`'s editing behaviour, including input-method marked text, selection, undo and the Services menu.
9. Where a caller needs to drive focus, the Design System's text input components shall accept focus as a binding rather than owning it.
10. The composite field component shall associate its label with its field for assistive technologies.

### Requirement 6: List Components
**Objective:** As a developer, I want list rows styled in one place and a list that handles
its own empty case, so that the host list and the key list are consistent without either
feature reinventing them.

#### Acceptance Criteria
1. The Design System shall provide list row appearance as a `ViewModifier` or a row view used within SwiftUI's native `List`.
2. The Design System shall not conform any type to `ListStyle`, which declares no public requirement.
3. The Design System shall provide a composite list component rendering a caller-supplied collection with caller-supplied row content.
4. The composite list component shall take its selection as a `Binding` owned by its caller.
5. The composite list component shall require the caller to supply a stable identity for each row.
6. When the supplied collection is empty, the composite list component shall render the empty-state component rather than an empty rows area.
7. While the list's content exceeds the height available in the panel, the composite list component shall scroll its rows within a bounded height rather than growing the panel.
8. The Design System's list components shall preserve the native `List`'s row selection, keyboard navigation and accessibility behaviour.

### Requirement 7: Status Indicator and Code Text
**Objective:** As a developer, I want the status row and monospaced path rendering that the
panel already hand-rolls to exist as components, so that every later feature reports state
and displays paths, fingerprints and config snippets the same way.

#### Acceptance Criteria
1. The Design System shall provide a status indicator component rendering an icon, a message and a semantic tint for a caller-supplied state.
2. The status indicator component's state shall be a closed type covering at least success, warning, failure and in-progress, in which an invalid combination cannot be expressed.
3. The status indicator component shall distinguish its states by icon as well as by tint.
4. The Design System shall provide a code text component rendering caller-supplied text in a monospaced face, which the user can select and copy.
5. If code text cannot fit the available width, then the code text component shall truncate it in the middle within a bounded number of lines, so that both ends of a path remain visible.
6. When the SSH directory status view is rendered, the MenuBar layer shall render the resolved path through the code text component and the reachability row through the status indicator component, presenting the same information it presents today.
7. The status indicator and code text components shall derive their content solely from caller-supplied inputs.

### Requirement 8: Empty State and Section Header
**Objective:** As a developer, I want the panel's structural pieces defined once, so that
"no hosts configured" and "no keys found" read as the same product rather than as two
separately invented screens.

#### Acceptance Criteria
1. The Design System shall provide an empty-state component rendering a caller-supplied message, an optional icon and an optional action.
2. Where an empty state carries an action, the empty-state component shall render it using the Design System's button components.
3. The Design System shall provide a section header component for grouping content within the panel.
4. The section header component shall render its title using the Design System's typography tokens.
5. The section header component shall be exposed to assistive technologies as a heading.
6. The empty-state and section header components shall lay out within the panel's fixed width without horizontal scrolling.

### Requirement 9: Toggle and Enumerated Choice Components
**Objective:** As a developer, I want boolean and enumerated value editors available as
components, so that the config feature edits `yes`/`no` keywords and enumerated values
without inventing its own controls.

#### Acceptance Criteria
1. The Design System shall provide toggle appearance as a `ToggleStyle` conformance applied to SwiftUI's native `Toggle`.
2. The Design System shall provide an enumerated-choice row as a composite component built on SwiftUI's native `Picker`.
3. The Design System shall not conform any type to `PickerStyle`, which declares no public requirement.
4. The toggle and enumerated-choice components shall take their value as a `Binding` owned by the caller.
5. The enumerated-choice component shall accept its options as a caller-supplied collection, and shall not enumerate any OpenSSH keyword or value itself.
6. When the caller supplies a collection of options, the enumerated-choice component shall render every supplied option and shall render no option the caller did not supply.
7. The toggle and enumerated-choice components shall preserve the native controls' keyboard activation and accessibility behaviour.

### Requirement 10: Secret Field Component
**Objective:** As a user, I want key material hidden unless I explicitly ask to see it, so
that opening the app in a screen share or over someone's shoulder never exposes a private
key.

#### Acceptance Criteria
1. The Design System shall provide a secret field component that renders a caller-supplied value in a redacted form.
2. While no reveal has been granted, the secret field component shall render no character of the value.
3. When the user requests a reveal, the secret field component shall report that request to its caller, and shall not reveal the value on its own authority.
4. While the caller reports the value as revealed, the secret field component shall render the value.
5. The secret field component shall not copy, log or persist the value.
6. The secret field component shall render only the value its caller supplies, and shall never read a file.
7. While a value is redacted, the secret field component shall not expose that value to assistive technologies.

### Requirement 11: Driven Component Contract
**Objective:** As a developer, I want components to be driven by their callers rather than
owning state, so that there is never a second source of truth for a value and every
component can be rendered in any state a test or preview asks for.

#### Acceptance Criteria
1. The Design System's components shall receive every value they display from their caller.
2. The Design System's components shall expose two-way values as a `Binding` owned by the caller.
3. The Design System's components shall expose actions as caller-supplied closures.
4. The Design System's components shall not declare `@State` for any value that has meaning outside the component.
5. Where a component keeps transient presentation state with no meaning to its caller, the Design System shall confine that state to the component and shall not let it alter the caller's data.
6. The Design System's components shall not construct or hold an observable model, a port conformer, or any application service.
7. If a component's inputs could describe a state it cannot render, then the Design System shall make that combination unrepresentable in the input type rather than resolving it at run time.

### Requirement 12: Adaptive Appearance and Accessibility
**Objective:** As a user, I want the app to respect my system appearance and accessibility
settings, so that a menu bar utility does not stand out as the one app ignoring them.

#### Acceptance Criteria
1. The Design System's components shall render legibly in both light and dark appearance.
2. When the user increases contrast, the Design System's components shall honour that setting.
3. When the user changes the system accent colour, the Design System's prominent components shall follow it.
4. When the user changes the system text size, the Design System's components shall scale their text and any spacing that depends on it.
5. The Design System's components shall not convey meaning by colour alone.
6. The Design System's components shall expose an accessibility label for every control and every non-decorative image.
7. While the panel is rendered over the menu bar's material, the Design System's components shall remain legible against it.

### Requirement 13: Component Testability
**Objective:** As a developer, I want appearance decisions unit-testable without rendering a
view, so that the project's test-first practice still applies to a layer whose output SwiftUI
gives no way to inspect.

#### Acceptance Criteria
1. The Design System shall express each appearance decision as a pure function or computed property on a value type, separate from the view that renders it.
2. When a test supplies a component state, the Design System shall return the corresponding icon, tint and emphasis for that state without rendering a view.
3. The Design System's token containers shall be readable from a test without constructing a view.
4. The Design System's tests shall run in the existing test target, which has no host application.
5. The Design System's tests shall not reference the file system, the user's home directory, or any literal SSH directory path.
6. Where a behaviour can only be verified visually, the Design System shall provide a SwiftUI preview covering each state of the component.
7. When `xcodebuild … test` is run for a macOS destination, the open-ssh-gui test target shall pass.

### Requirement 14: Temporary Component Showcase
**Objective:** As a developer, I want the running app to demonstrate every component at the
panel's real width, so that I can judge the design system in situ and delete the
demonstration in one step when the next feature replaces it.

#### Acceptance Criteria
1. When the user opens the menu bar panel, the open-ssh-gui app shall present a showcase rendering every Design System component.
2. The showcase shall render each component in every state its input type can express.
3. The showcase shall present the components at the panel's existing fixed width, without horizontal scrolling.
4. The showcase shall contain the components in a scrolling region of bounded height, so that the panel's size does not change as the showcase's content changes.
5. When the panel opens, the open-ssh-gui app shall lay the showcase out without triggering AppKit layout recursion.
6. The showcase shall retain the panel's existing Quit control, outside the scrolling region.
7. The showcase shall drive every component from values it declares itself, and shall not read the SSH directory.
8. The showcase shall be confined to source files that can be deleted without editing any Design System file, so that its removal is those deletions plus the single line that presents it.
9. The open-ssh-gui app shall mark the showcase's source as temporary, recording that the next feature spec removes it.
10. The open-ssh-gui app shall keep `MenuBarExtra` as its only scene.
