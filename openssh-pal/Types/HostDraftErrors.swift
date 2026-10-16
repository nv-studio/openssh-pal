import Foundation

/// Every rejection in a draft, keyed by the field it belongs beside.
nonisolated struct HostDraftErrors: Error, Sendable, Equatable {
    let byField: [HostDraftField: HostDraftError]
}
