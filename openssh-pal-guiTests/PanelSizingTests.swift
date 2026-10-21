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

    /// Every model a panel needs, over a fabricated directory holding `keyCount` pairs and the
    /// given `config` (none when `nil`).
    private struct Models {
        let list: SSHKeyListModel
        let form: NewKeyFormModel
        let status: SSHDirectoryStatusModel
        let configuration: SSHConfigModel
        let hostForm: HostFormModel

        func load() async {
            await list.refresh()
            await configuration.refresh()
        }

        var panel: PanelView {
            PanelView(status: status, keys: list, newKey: form, configuration: configuration, hostForm: hostForm)
        }
    }

    private static func models(keyCount: Int, config: String? = nil) -> Models {
        let line = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHG/eTv0q9SPBgITfzHoiFX9BXBTCO4InzbH19BagKve user@host"
        let names = (1...max(keyCount, 1)).map { "key_\($0)" }
        var entries = keyCount == 0 ? [] : names.flatMap { [$0, "\($0).pub"] }
        var files = Dictionary(
            uniqueKeysWithValues: names.map { (keys.appending(path: "\($0).pub"), Data(line.utf8)) }
        )
        if let config {
            entries.append("config")
            files[keys.appending(path: "config")] = Data(config.utf8)
        }

        let reader = InMemorySSHDirectoryReader(
            directories: [keys: entries.map { keys.appending(path: $0) }],
            files: files
        )

        let status = SSHDirectoryStatusModel(
            resolver: SSHDirectoryResolver(reader: reader),
            launchEnvironment: override(keys),
            homeDirectory: URL(filePath: "/fabricated/home", directoryHint: .isDirectory),
            reader: reader
        )

        let configuration = SSHConfigModel(
            status: status,
            reader: reader,
            writer: InMemorySSHConfigWriter(),
            homeDirectory: URL(filePath: "/fabricated/home", directoryHint: .isDirectory),
            userName: "alice"
        )

        let list = SSHKeyListModel(
            status: status,
            reader: reader,
            writer: InMemorySSHKeyWriter(),
            clipboard: RecordingClipboardWriter(),
            hostReferences: configuration
        )

        let form = NewKeyFormModel(
            generator: StubSSHKeyGenerator(outcome: .failure(.timedOut)),
            defaultComment: "user@host"
        )

        return Models(
            list: list,
            form: form,
            status: status,
            configuration: configuration,
            hostForm: HostFormModel(configuration: configuration, keys: list)
        )
    }

    private static func renderedSize(of view: some View) -> CGSize? {
        let renderer = ImageRenderer(content: view)
        return renderer.nsImage?.size
    }

    @Test("The key list surface is explicitly sized, so its contents cannot change its height")
    func keyListSurfaceIsAlwaysOneSize() async throws {
        var sizes: Set<String> = []

        for keyCount in [0, 1, 12] {
            let models = Self.models(keyCount: keyCount)
            await models.load()

            let size = try #require(
                Self.renderedSize(of: SSHKeyListView(model: models.list, status: models.status))
            )
            sizes.insert("\(size.width)x\(size.height)")
        }

        #expect(sizes.count == 1, "the surface changed size with its contents: \(sizes)")
    }

    @Test("Both surfaces are the same exact size, so switching the route cannot resize the panel")
    func bothSurfacesAreTheSameSize() async throws {
        let models = Self.models(keyCount: 12)
        await models.load()
        models.form.begin(in: SSHDirectory(url: Self.keys), existing: [])

        let listSize = try #require(Self.renderedSize(of: SSHKeyListView(model: models.list, status: models.status)))
        let formSize = try #require(Self.renderedSize(of: NewKeyFormView(model: models.form) {}))

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

        let models = Self.models(keyCount: 12)
        await models.load()
        models.form.begin(in: SSHDirectory(url: Self.keys), existing: [])

        for surface in [
            AnyView(SSHKeyListView(model: models.list, status: models.status)),
            AnyView(NewKeyFormView(model: models.form) {}),
        ] {
            let size = try #require(Self.renderedSize(of: surface))
            #expect(size.width == PanelMetrics.contentWidth)
        }
    }

    @Test("The panel is the sum of its regions, so no slack collects under Quit")
    func panelIsTheSumOfItsRegions() {
        #expect(
            PanelMetrics.height
                == PanelMetrics.edgeInset * 2
                + PanelMetrics.tabContainerHeight
                + PanelMetrics.bodyContainerHeight
                + PanelMetrics.footerHeight
                + Spacing.regular * 2
        )
        #expect(PanelMetrics.contentInset == PanelMetrics.edgeInset + PanelMetrics.containerPadding)
        #expect(PanelMetrics.tabBarHeight > 0)
    }

    @Test("The tab bar is its token's height, whichever option is selected")
    func tabBarIsOneHeight() throws {
        for selected in ["Keys", "Hosts", "New Key"] {
            let bar = TabBar(label: "Sections", options: ["Keys", "Hosts", "New Key"], selection: .constant(selected)) { $0 }
                .frame(width: PanelMetrics.contentWidth)
            let size = try #require(Self.renderedSize(of: bar))
            #expect(size.height == PanelMetrics.tabBarHeight)
            #expect(size.width == PanelMetrics.contentWidth)
        }
    }

    // MARK: - crud-ssh-config-hosts 10.11 / 10.12 / 12.8 tabs and host surfaces

    /// The appearances and text sizes every surface is rendered in.
    private static let environments: [(ColorScheme, DynamicTypeSize)] = [
        (.light, .large), (.dark, .large), (.light, .accessibility5), (.dark, .accessibility5),
    ]

    private static func renderedSize(of view: some View, in environment: (ColorScheme, DynamicTypeSize)) -> CGSize? {
        renderedSize(
            of: view
                .environment(\.colorScheme, environment.0)
                .environment(\.dynamicTypeSize, environment.1)
        )
    }

    private static let hostConfig = (1...12)
        .map { "Host host-\($0)\n    HostName host-\($0).example.com\n    User deploy\n    IdentityFile /fabricated/keys/key_1\n" }
        .joined() + "Include %h\n"

    @Test("Every tab's surface and every host surface is one size, in every appearance and text size")
    func everySurfaceIsOneSize() async throws {
        let loaded = Self.models(keyCount: 3, config: Self.hostConfig)
        await loaded.load()
        let noConfig = Self.models(keyCount: 0)
        await noConfig.load()
        let loading = Self.models(keyCount: 0, config: "Host a\n")

        let edited = Self.models(keyCount: 3, config: Self.hostConfig)
        await edited.load()
        edited.hostForm.beginEdit(try #require(edited.configuration.entries.first))

        let created = Self.models(keyCount: 3, config: Self.hostConfig)
        await created.load()
        created.hostForm.beginCreate()
        created.hostForm.draft.patterns = "new"

        let generating = Self.models(keyCount: 3)
        await generating.load()
        generating.form.begin(in: SSHDirectory(url: Self.keys), existing: [])

        let surfaces: [(String, AnyView)] = [
            ("keys", AnyView(SSHKeyListView(model: loaded.list, status: loaded.status))),
            ("hosts", AnyView(HostListView(configuration: loaded.configuration, keys: loaded.list, form: loaded.hostForm))),
            ("no config", AnyView(HostListView(configuration: noConfig.configuration, keys: noConfig.list, form: noConfig.hostForm))),
            ("loading", AnyView(HostListView(configuration: loading.configuration, keys: loading.list, form: loading.hostForm))),
            ("hosts tab, list", AnyView(HostsTabView(configuration: loaded.configuration, keys: loaded.list, form: loaded.hostForm))),
            ("hosts tab, edit", AnyView(HostsTabView(configuration: edited.configuration, keys: edited.list, form: edited.hostForm))),
            ("create form", AnyView(HostFormView(model: created.hostForm))),
            ("new key", AnyView(NewKeyFormView(model: generating.form) {})),
        ]

        for environment in Self.environments {
            for (name, surface) in surfaces {
                let size = try #require(Self.renderedSize(of: surface, in: environment), "\(name)")
                #expect(size.width == PanelMetrics.contentWidth, "\(name) \(environment)")
                #expect(size.height == PanelMetrics.surfaceHeight, "\(name) \(environment)")
            }
        }
    }

    @Test("The panel is its exact size in every appearance and text size, with hosts loaded")
    func panelIsOneSizeEverywhere() async throws {
        let models = Self.models(keyCount: 12, config: Self.hostConfig)
        await models.load()

        for environment in Self.environments {
            let size = try #require(Self.renderedSize(of: models.panel, in: environment))
            #expect(size.width == PanelMetrics.width)
            #expect(size.height == PanelMetrics.height)
        }
    }

    @Test("The whole panel is explicitly sized to the exact height its token names")
    func panelIsTheExactTokenHeight() async throws {
        let models = Self.models(keyCount: 12)
        await models.load()

        let size = try #require(Self.renderedSize(of: models.panel))

        #expect(size.width == PanelMetrics.width)
        #expect(size.height == PanelMetrics.height)
    }
}
