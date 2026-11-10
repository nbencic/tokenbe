import Foundation

/// What one poll needs (14 § Stage 3.3 step 3). Built by the poller for a single job and dropped after it, so the
/// key lives only as long as the request (R8).
public struct PollContext: Sendable {
  public var accountID: String
  public var key: String
  /// The paging cursor saved in `poll_state.cursor`, if a page sequence was interrupted.
  public var cursor: String?
  public var window: DateInterval
  public var transport: any HTTPTransport
  public var clock: any Clock<Duration>

  public init(accountID: String, key: String, cursor: String?, window: DateInterval, transport: any HTTPTransport,
              clock: any Clock<Duration>) {
    self.accountID = accountID
    self.key = key
    self.cursor = cursor
    self.window = window
    self.transport = transport
    self.clock = clock
  }
}

/// A provider key the probe or a keys poll found (02). No `account_id` yet at probe time, so not a record.
public struct DiscoveredKey: Sendable, Equatable {
  /// OpenAI `key_…`, Anthropic `apikey_…`, OpenRouter hash (03 `provider_key.provider_key_id`).
  public var providerKeyID: String
  public var name: String?
  public var redacted: String?
  public var projectID: String?
  public var workspaceID: String?

  public init(providerKeyID: String, name: String? = nil, redacted: String? = nil, projectID: String? = nil,
              workspaceID: String? = nil) {
    self.providerKeyID = providerKeyID
    self.name = name
    self.redacted = redacted
    self.projectID = projectID
    self.workspaceID = workspaceID
  }
}

/// Onboarding's "Test connection" (02 § Probe; 08 step 2).
public struct ProbeResult: Sendable, Equatable {
  public var capabilities: Capabilities
  /// Shown on failure instead of raw JSON (08): one of 02's human messages.
  public var humanMessage: String?
  public var discoveredKeys: [DiscoveredKey]
  public var orgID: String?
  public var orgName: String?
  public var currency: Currency
  /// Each probe step's response body after `Redactor`, by endpoint name, for diagnostics.
  public var rawBodiesRedacted: [String: String]

  public init(capabilities: Capabilities, humanMessage: String? = nil, discoveredKeys: [DiscoveredKey] = [],
              orgID: String? = nil, orgName: String? = nil, currency: Currency,
              rawBodiesRedacted: [String: String] = [:]) {
    self.capabilities = capabilities
    self.humanMessage = humanMessage
    self.discoveredKeys = discoveredKeys
    self.orgID = orgID
    self.orgName = orgName
    self.currency = currency
    self.rawBodiesRedacted = rawBodiesRedacted
  }
}

/// One page of a usage poll: rows to upsert, the cursor of the next page, and the redacted body for `last_raw`.
public struct UsagePage: Sendable, Equatable {
  public var rows: [UsageBucketRecord]
  public var nextCursor: String?
  public var rawBody: String

  public init(rows: [UsageBucketRecord], nextCursor: String?, rawBody: String) {
    self.rows = rows
    self.nextCursor = nextCursor
    self.rawBody = rawBody
  }
}

/// A cost poll's rows and redacted body.
public struct CostPage: Sendable, Equatable {
  public var rows: [CostBucketRecord]
  public var rawBody: String

  public init(rows: [CostBucketRecord], rawBody: String) {
    self.rows = rows
    self.rawBody = rawBody
  }
}

/// A balance poll's snapshots (one per currency, 02 § deepseek) and redacted body.
public struct BalanceReading: Sendable, Equatable {
  public var snapshots: [BalanceSnapshotRecord]
  public var rawBody: String

  public init(snapshots: [BalanceSnapshotRecord], rawBody: String) {
    self.snapshots = snapshots
    self.rawBody = rawBody
  }
}

/// A keys poll's provider keys and redacted body.
public struct KeysPage: Sendable, Equatable {
  public var keys: [DiscoveredKey]
  public var rawBody: String

  public init(keys: [DiscoveredKey], rawBody: String) {
    self.keys = keys
    self.rawBody = rawBody
  }
}

/// One provider's API (14 § 0.3 Provider seam; 02). The scheduler runs only the jobs `Capabilities` allows, so a
/// provider implements only the polls 02 gives it; the others answer `providerRule` (07 `poll.provider_rule`).
public protocol ProviderAdapter: Sendable {
  var id: ProviderID { get }
  /// Never throws: every failure becomes a `ProbeResult` with a `humanMessage` (02 § Probe).
  func probe(key: String, transport: any HTTPTransport) async -> ProbeResult
  func pollUsage(_ context: PollContext) async throws(PollError) -> UsagePage
  func pollCost(_ context: PollContext) async throws(PollError) -> CostPage
  func pollBalance(_ context: PollContext) async throws(PollError) -> BalanceReading
  func pollKeys(_ context: PollContext) async throws(PollError) -> KeysPage
}

extension ProviderAdapter {
  public func pollUsage(_ context: PollContext) async throws(PollError) -> UsagePage {
    throw .providerRule("\(id.rawValue)_no_usage_api")
  }

  public func pollCost(_ context: PollContext) async throws(PollError) -> CostPage {
    throw .providerRule("\(id.rawValue)_no_cost_api")
  }

  public func pollBalance(_ context: PollContext) async throws(PollError) -> BalanceReading {
    throw .providerRule("\(id.rawValue)_no_balance_api")
  }

  public func pollKeys(_ context: PollContext) async throws(PollError) -> KeysPage {
    throw .providerRule("\(id.rawValue)_no_keys_api")
  }
}
