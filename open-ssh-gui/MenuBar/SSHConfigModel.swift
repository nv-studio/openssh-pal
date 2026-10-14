import Foundation
import Observation

/// Owns the loaded configuration and every change made to it.
///
/// `@MainActor @Observable`, and the single source of truth for what the Hosts tab presents. It
/// composes the pure rules with the two ports and decides nothing about text: parsing, matching,
/// placement and editing are separate types, tested on their own.
///
/// No initializer parameter has a default value, following `SSHKeyListModel`: forgetting to
/// inject the writer is then a compile error rather than a silent fallback to the real file
/// system — for the first component that writes `~/.ssh/config`, the difference between a
/// failing build and a damaged configuration.
///
/// Every write is the direct result of a call below, and every call below is reached only from a
/// control the user confirmed. Nothing here writes on load, on refresh or on a timer.
@MainActor
@Observable
final class SSHConfigModel: HostReferenceLookup {

    // MARK: - Presented state

    private(set) var state: SSHConfigState = .loading

    /// Whether a load is in flight. Separate from `state` so a refresh does not empty the list.
    private(set) var isRefreshing = false

    /// The change in flight. No case for two, which is what refuses a second one.
    private(set) var operation: ConfigOperation = .idle

    private(set) var notice: ConfigNotice?

    /// What resolving a path needs, for the directory the last refresh resolved. `nil` when no
    /// directory resolved.
    private(set) var context: IdentityResolutionContext?

    // MARK: - Dependencies

    private let status: SSHDirectoryStatusModel
    private let reader: SSHDirectoryReading
    private let writer: SSHConfigWriting
    private let homeDirectory: URL
    private let userName: String

    private let parser = SSHConfigParser()
    private let associator = HostKeyAssociator()
    private let editor = HostBlockEditor()
    private let placer = HostBlockPlacement()
    private let backups = ConfigBackupLocation()

    /// - Parameters:
    ///   - homeDirectory: what `~` and `%d` mean. Injected because only the composition root may
    ///     ask the process for it.
    ///   - userName: what `%u` means, for the same reason.
    init(
        status: SSHDirectoryStatusModel,
        reader: SSHDirectoryReading,
        writer: SSHConfigWriting,
        homeDirectory: URL,
        userName: String
    ) {
        self.status = status
        self.reader = reader
        self.writer = writer
        self.homeDirectory = homeDirectory
        self.userName = userName
    }

    // MARK: - Loading

    /// Re-reads the directory status and the configuration. Driven at launch, on each panel open
    /// and after every change.
    ///
    /// Never throws: every failure becomes a state or an issue. Skipped while a change is in
    /// flight, because reading a file mid-write would race it — and the change re-reads when it
    /// finishes anyway.
    func refresh() async {
        guard !operation.isInFlight else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        await status.refresh()

        switch status.status {
        case .resolving:
            // Unreachable after an awaited refresh; treated as still loading rather than
            // asserted, because a crash here would cost the user their only way to quit.
            state = .loading
        case .unresolved(let error):
            context = nil
            state = .noDirectory(error)
        case .unreadable(let directory, let error):
            context = makeContext(for: directory)
            state = .unreadable(error)
        case .reachable(let directory):
            let context = makeContext(for: directory)
            self.context = context
            state = await load(directory, context: context)
        }
    }

    private func load(_ directory: SSHDirectory, context: IdentityResolutionContext) async -> SSHConfigState {
        switch await SSHConfigLoader(reader: reader, parser: parser).load(in: directory, context: context) {
        case .noConfigFile:
            .noConfigFile
        case .unreadable(let error):
            .unreadable(error)
        case .loaded(let configuration):
            .loaded(await downgradingLinkedFiles(in: configuration, directory: directory))
        }
    }

    /// Marks read-only every file whose real location — symbolic links followed — is outside
    /// the directory. The loader cannot see links; the writer can, and would refuse the write
    /// anyway, so the user is told up front instead of on save.
    private func downgradingLinkedFiles(in configuration: SSHConfiguration, directory: SSHDirectory) async -> SSHConfiguration {
        let root = IdentityResolutionContext.normalizedPath(of: await writer.resolvedLocation(of: directory.url))
        var files = configuration.files
        var downgraded: Set<URL> = []

        for (index, file) in files.enumerated() where file.writability.isWritable {
            let resolved = IdentityResolutionContext.normalizedPath(of: await writer.resolvedLocation(of: file.url))
            if !resolved.hasPrefix(root + "/") {
                files[index] = file.withWritability(.readOnly(.symbolicLinkOutsideDirectory))
                downgraded.insert(file.url)
            }
        }

        guard !downgraded.isEmpty else { return configuration }
        return configuration.with(
            files: files,
            entries: configuration.entries.map {
                downgraded.contains($0.file) ? $0.withWritability(.readOnly(.symbolicLinkOutsideDirectory)) : $0
            }
        )
    }

    private func makeContext(for directory: SSHDirectory) -> IdentityResolutionContext {
        IdentityResolutionContext(
            homeDirectory: homeDirectory,
            sshDirectory: directory,
            userName: userName,
            defaultDirectory: homeDirectory.appending(path: SSHDirectoryResolver.directoryName)
        )
    }

    // MARK: - Projections

    var configuration: SSHConfiguration? { state.configuration }

    var entries: [HostEntry] { configuration?.entries ?? [] }

    /// Which key each host uses, for the pairs the Keys tab lists. Recomputed per call: a
    /// configuration is small, and a stale index would show a warning that no longer applies.
    func keyIndex(for pairs: [SSHKeyPair]) -> HostKeyIndex {
        guard let configuration, let context else { return .empty }
        return associator.index(configuration, pairs: pairs, context: context)
    }

    /// Where a new block for `alias` would go, and what would still precede it.
    func placement(for alias: String) -> PlacementDecision? {
        configuration.map { placer.place(alias: alias, in: $0) }
    }

    /// The bytes an edit of `entry` is computed against: its file as this load read it.
    func baseline(for entry: HostEntry) -> Data? {
        configuration?.file(at: entry.file)?.original
    }

    /// The bytes a creation is computed against: `config` as this load read it, or `nil` when
    /// there was no `config` to read.
    var configBaseline: Data? {
        configuration?.root?.original
    }

    /// A file's location as the user knows it: relative to the SSH directory when inside it.
    func displayPath(of url: URL) -> String {
        let path = IdentityResolutionContext.normalizedPath(of: url)
        guard let context, context.contains(url) else { return path }
        let root = IdentityResolutionContext.normalizedPath(of: context.sshDirectory.url)
        return String(path.dropFirst(root.count + 1))
    }

    /// What the host list renders, for the pairs the Keys tab lists.
    func presentations(for pairs: [SSHKeyPair]) -> [HostEntryPresentation] {
        let index = keyIndex(for: pairs)
        let root = configuration?.root?.url
        return entries.map {
            HostEntryPresentation(
                entry: $0,
                associations: index.associations(for: $0.id),
                sharingHosts: index.sharingHosts(for: $0.id),
                file: displayPath(of: $0.file),
                isDeclaredInConfig: $0.file == root
            )
        }
    }

    /// The first load issue, with how many more there are.
    var issueSummary: String? {
        guard let issues = configuration?.issues, let first = issues.first else { return nil }
        return issues.count == 1 ? first.message : "\(first.message) (and \(issues.count - 1) more)"
    }

    /// Whether a host can be added at all: `config` exists and may be written, or does not
    /// exist and may be created.
    var canCreate: Bool {
        switch state {
        case .loaded(let configuration): configuration.root?.writability.isWritable ?? false
        case .noConfigFile: true
        case .loading, .unreadable, .noDirectory: false
        }
    }

    func dismissNotice() {
        notice = nil
    }

    // MARK: - Editing

    /// Writes `draft` over the block `entry` describes, in the file that declares it.
    ///
    /// The edit is computed from `baseline` — the bytes the form was opened against — never
    /// from whatever was loaded since. The writer then replaces the file only if it still holds
    /// exactly those bytes, so an edit made in a text editor meanwhile is never overwritten.
    func update(_ entry: HostEntry, with draft: ValidatedHostDraft, baseline: Data) async -> ConfigMutationOutcome {
        guard !operation.isInFlight else { return .refused }
        guard entry.writability.isWritable, let context, let configuration else {
            notice = .failed(reason: entry.writability.readOnlyReason ?? "There is no configuration to change.")
            return .refused
        }

        // Re-read from the baseline, so the line numbers the edit uses are the ones the entry
        // was read with.
        let file = parser.parse(
            baseline,
            at: entry.file,
            inclusionChain: configuration.file(at: entry.file)?.inclusionChain ?? [],
            writability: entry.writability
        )
        guard file.entries.contains(where: { $0.id == entry.id && $0.withWritability(entry.writability) == entry }) else {
            notice = .changedOnDisk(fileName: displayPath(of: entry.file))
            await refresh()
            return .changedOnDisk
        }

        operation = .updating(entry.id)
        let outcome = await write(
            editor.applying(draft, to: entry, in: file.file, context: context),
            to: entry.file,
            baseline: baseline,
            in: context.sshDirectory,
            avoiding: configuration.includePatterns
        )
        if outcome == .completed { notice = .updated(draft.patterns.joined(separator: " ")) }

        operation = .idle
        await refresh()
        return outcome
    }

    // MARK: - Deleting

    func deletionTitle(for entry: HostEntry) -> String {
        "Delete Host \(entry.displayName)?"
    }

    /// Names the entry and the file, and says what is *not* deleted.
    func deletionMessage(for entry: HostEntry) -> String {
        """
        Host \(entry.displayName) and the comments directly above it are removed from \
        \(displayPath(of: entry.file)). Its key pair is not deleted, and the file is backed up \
        before its first change.
        """
    }

    /// Removes the block. Reached only once the user has confirmed; declining means this is
    /// never called, and then nothing has been touched.
    func delete(_ entry: HostEntry) async -> ConfigMutationOutcome {
        guard !operation.isInFlight else { return .refused }
        guard entry.writability.isWritable, let context, let configuration,
              let file = configuration.file(at: entry.file),
              configuration.entries.contains(entry)
        else {
            notice = .failed(reason: entry.writability.readOnlyReason ?? "That host is no longer in the configuration.")
            return .refused
        }

        operation = .deleting(entry.id)
        let outcome = await write(
            editor.removing(entry, from: file),
            to: file.url,
            baseline: file.original,
            in: context.sshDirectory,
            avoiding: configuration.includePatterns
        )
        if outcome == .completed { notice = .deleted(entry.displayName) }

        operation = .idle
        await refresh()
        return outcome
    }

    // MARK: - Creating

    /// Adds a block for `draft` to `config`, where `HostBlockPlacement` says it goes, or creates
    /// `config` holding only that block.
    ///
    /// - Parameter baseline: `config`'s bytes when the form opened, or `nil` if there was no
    ///   `config`. A `config` that appeared or changed since is not written.
    func create(_ draft: ValidatedHostDraft, baseline: Data?) async -> ConfigMutationOutcome {
        guard !operation.isInFlight else { return .refused }
        guard let context else {
            notice = .failed(reason: state.failureReason ?? "No SSH directory resolved, so there is nowhere to add a host.")
            return .refused
        }

        let outcome: ConfigMutationOutcome

        switch state {
        case .loaded(let configuration):
            guard let root = configuration.root, root.writability.isWritable else {
                notice = .failed(reason: configuration.root?.writability.readOnlyReason ?? "There is no config file to change.")
                return .refused
            }
            guard let baseline, baseline == root.original else {
                notice = .changedOnDisk(fileName: displayPath(of: root.url))
                await refresh()
                return .changedOnDisk
            }

            operation = .creating
            let decision = placer.place(alias: draft.alias, in: configuration)
            outcome = await write(
                editor.inserting(draft, at: decision.point, in: root, context: context),
                to: root.url,
                baseline: baseline,
                in: context.sshDirectory,
                avoiding: configuration.includePatterns
            )

        case .noConfigFile:
            let config = context.sshDirectory.url.appending(path: SSHConfigLoader.configFileName)
            guard baseline == nil else {
                notice = .changedOnDisk(fileName: displayPath(of: config))
                await refresh()
                return .changedOnDisk
            }

            // No backup: the app is creating this file, so there is nothing of the user's to
            // keep a copy of.
            operation = .creating
            outcome = await createFile(config, with: editor.newFile(containing: draft, context: context), in: context.sshDirectory)

        case .unreadable(.directoryNotFound(let url)) where url == context.sshDirectory.url:
            // Not created: making `~/.ssh` is a decision with permissions consequences the user
            // has not been asked about.
            notice = .failed(reason: "The SSH directory does not exist: \(url.path(percentEncoded: false))")
            return .refused

        case .loading, .unreadable, .noDirectory:
            notice = .failed(reason: state.failureReason ?? "The configuration has not been read yet.")
            return .refused
        }

        if outcome == .completed { notice = .created(draft.alias) }

        operation = .idle
        await refresh()
        return outcome
    }

    // MARK: - Writing

    /// Backs the file up if it has never been, then replaces it if it still holds `baseline`.
    private func write(
        _ contents: Data,
        to file: URL,
        baseline: Data,
        in directory: SSHDirectory,
        avoiding includes: [GlobPath]
    ) async -> ConfigMutationOutcome {
        let backup: URL
        switch backups.backupURL(for: await writer.resolvedLocation(of: file), avoiding: includes) {
        case .success(let url):
            backup = url
        case .failure(let error):
            notice = .failed(reason: error.reason)
            return .failed
        }

        do {
            _ = try await writer.backUpIfAbsent(file, to: backup, within: directory)
            try await writer.replace(file, expecting: baseline, with: contents, within: directory)
            return .completed
        } catch .changedOnDisk {
            notice = .changedOnDisk(fileName: displayPath(of: file))
            return .changedOnDisk
        } catch {
            notice = .failed(reason: error.reason)
            return .failed
        }
    }

    private func createFile(_ file: URL, with contents: Data, in directory: SSHDirectory) async -> ConfigMutationOutcome {
        do {
            try await writer.create(file, with: contents, within: directory)
            return .completed
        } catch .alreadyExists {
            notice = .changedOnDisk(fileName: displayPath(of: file))
            return .changedOnDisk
        } catch {
            notice = .failed(reason: error.reason)
            return .failed
        }
    }

    // MARK: - HostReferenceLookup

    /// The hosts whose `IdentityFile` resolves to `pair`.
    ///
    /// Part of the configuration that could not be read might name the key too, so an
    /// unreadable or skipped include counts as an unresolved reference.
    func hostReferences(to pair: SSHKeyPair) -> HostReferenceReport {
        switch state {
        case .loading:
            return .unavailable(reason: "The SSH configuration has not been read yet.")
        case .unreadable, .noDirectory:
            return .unavailable(reason: state.failureReason ?? "The SSH configuration could not be read.")
        case .noConfigFile:
            return .references(hosts: [], hasUnresolved: false)
        case .loaded(let configuration):
            let index = keyIndex(for: [pair])
            let files = [pair.location.privateKeyURL, pair.location.publicKeyURL].compactMap(\.self)
            let referencing = Set(files.flatMap(index.entries(referencing:)))

            var hosts: [String] = []
            for entry in configuration.entries where referencing.contains(entry.id) && !hosts.contains(entry.displayName) {
                hosts.append(entry.displayName)
            }

            let partlyUnread = configuration.issues.contains {
                switch $0 {
                case .unreadable, .skippedInclude, .includeDepthExceeded: true
                case .unparseableLine, .includeCycle: false
                }
            }
            return .references(hosts: hosts, hasUnresolved: index.hasUnresolvedReferences || partlyUnread)
        }
    }
}
