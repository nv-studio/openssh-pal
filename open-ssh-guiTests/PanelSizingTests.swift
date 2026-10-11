import Foundation
import SwiftUI
import Testing

/// What can be checked about the panel's size without a host application.
///
/// **What these prove**: that every surface is *explicitly* sized rather than sized to its
/// content, that the two surfaces are the same size, and that the panel is the exact height
/// its token names. That is the mechanism the design depends on — a content-sized panel is
/// what produces `_NSDetectedLayoutRecursion`, and a route switch that changed the size is
/// what would resize the panel.
///
/// **What they do not prove**: that the content fits inside those bounds without clipping, or
/// that no layout-recursion diagnostic appears across repeated real opens. A `frame(height:)`
/// reports its own height whatever is inside it, so overflow is invisible here; and the panel
/// has to actually be opened for AppKit to complain. Both need a launch and a click, which the
/// test target deliberately cannot do — it has no host application, because a host would
/// launch the app against the developer's real SSH directory on every run.
@MainActor
@Suite("Panel sizing")
struct PanelSizingTests {

    nonisolated private static let keys = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)

    nonisolated private static func override(_ url: URL) -> LaunchEnvironment {
        LaunchEnvironment(
            arguments: [LaunchEnvironment.overrideArgument, url.path(percentEncoded: false)],
            environmentVariables: [:]
        )
    }

    private static func models(keyCount: Int) -> (SSHKeyListModel, NewKeyFormModel, SSHDirectoryStatusModel) {
        let line = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHG/eTv0q9SPBgITfzHoiFX9BXBTCO4InzbH19BagKve user@host"
        let names = (1...max(keyCount, 1)).map { "key_\($0)" }
        let entries = keyCount == 0 ? [] : names.flatMap { [$0, "\($0).pub"] }

        let reader = InMemorySSHDirectoryReader(
            directories: [keys: entries.map { keys.appending(path: $0) }],
            files: Dictionary(
                uniqueKeysWithValues: names.map { (keys.appending(path: "\($0).pub"), Data(line.utf8)) }
            )
        )

        let status = SSHDirectoryStatusModel(
            resolver: SSHDirectoryResolver(reader: reader),
            launchEnvironment: override(keys),
            homeDirectory: URL(filePath: "/fabricated/home", directoryHint: .isDirectory),
            reader: reader
        )

        let list = SSHKeyListModel(
            status: status,
            reader: reader,
            writer: InMemorySSHKeyWriter(),
            clipboard: RecordingClipboardWriter()
        )

        let form = NewKeyFormModel(
            generator: StubSSHKeyGenerator(outcome: .failure(.timedOut)),
            defaultComment: "user@host"
        )

        return (list, form, status)
    }

    private static func renderedSize(of view: some View) -> CGSize? {
        let renderer = ImageRenderer(content: view)
        return renderer.nsImage?.size
    }

    @Test("The key list surface is explicitly sized, so its contents cannot change its height")
    func keyListSurfaceIsAlwaysOneSize() async throws {
        var sizes: Set<String> = []

        for keyCount in [0, 1, 12] {
            let (list, _, status) = Self.models(keyCount: keyCount)
            await list.refresh()

            let size = try #require(
                Self.renderedSize(of: SSHKeyListView(model: list, status: status) {})
            )
            sizes.insert("\(size.width)x\(size.height)")
        }

        #expect(sizes.count == 1, "the surface changed size with its contents: \(sizes)")
    }

    @Test("Both surfaces are the same exact size, so switching the route cannot resize the panel")
    func bothSurfacesAreTheSameSize() async throws {
        let (list, form, status) = Self.models(keyCount: 12)
        await list.refresh()
        form.begin(in: SSHDirectory(url: Self.keys), existing: [])

        let listSize = try #require(Self.renderedSize(of: SSHKeyListView(model: list, status: status) {}))
        let formSize = try #require(Self.renderedSize(of: NewKeyFormView(model: form) {}))

        #expect(listSize == formSize)
        #expect(listSize.width == PanelMetrics.contentWidth)
        #expect(listSize.height == PanelMetrics.surfaceHeight)
    }

    @Test("A surface is laid out inside the panel's gutter rather than across it")
    func surfacesRespectTheGutter() async throws {
        // The panel pads its content and then clamps itself to `width`. A surface that stated
        // `width` was proposed the narrower width, insisted on the wider one, and was drawn
        // edge to edge — the gutter cancelled for the one region that fills the panel, while
        // the divider and Quit beneath it kept theirs.
        #expect(PanelMetrics.contentWidth + PanelMetrics.contentInset * 2 == PanelMetrics.width)

        let (list, form, status) = Self.models(keyCount: 12)
        await list.refresh()
        form.begin(in: SSHDirectory(url: Self.keys), existing: [])

        for surface in [
            AnyView(SSHKeyListView(model: list, status: status) {}),
            AnyView(NewKeyFormView(model: form) {}),
        ] {
            let size = try #require(Self.renderedSize(of: surface))
            #expect(size.width == PanelMetrics.contentWidth)
        }
    }

    @Test("The whole panel is explicitly sized to the exact height its token names")
    func panelIsTheExactTokenHeight() async throws {
        let (list, form, status) = Self.models(keyCount: 12)
        await list.refresh()

        let size = try #require(
            Self.renderedSize(of: PanelView(status: status, keys: list, form: form))
        )

        #expect(size.width == PanelMetrics.width)
        #expect(size.height == PanelMetrics.height)
    }
}
