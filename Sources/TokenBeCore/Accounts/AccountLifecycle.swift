import Foundation

/// An account from onboarding to removal (14 § Stage 3.5): the probe behind `Test & continue` and `Test`, the
/// writes after a successful probe, `Replace key…`, `Remove account…`, the onboarding anchor, and startup step 3's
/// Keychain check (04). The UI calls these and renders their results; it never touches the store or the Keychain.
public struct AccountLifecycle: Sendable {
  /// 14 § Stage 3.5 step 1: the probe gives up after 10 s with the transport error message.
  public static let probeTimeout = Duration.seconds(10)

  let repository: any Repository
  let keyStore: any KeyStore
  let registry: ProviderRegistry
  let transport: any HTTPTransport
  let clock: any Clock<Duration>
  let log: EventLog
  let now: @Sendable () -> Date

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(repository: any Repository, keyStore: any KeyStore, registry: ProviderRegistry,
              transport: any HTTPTransport, clock: any Clock<Duration> = ContinuousClock(),
              logPipeline: LogPipeline? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
    self.repository = repository
    self.keyStore = keyStore
    self.registry = registry
    self.transport = transport
    self.clock = clock
    self.log = EventLog(pipeline: logPipeline)
    self.now = now
  }

  // MARK: - Probe

  /// The provider's probe (02), bounded by `probeTimeout`. `humanMessage == nil` means it passed (Q-029).
  public func probe(_ provider: ProviderID, key: String) async -> ProbeResult {
    let key = ProviderID.normalizedKey(key)
    guard let adapter = registry.adapter(for: provider) else {
      return Self.failed(CoreStrings.unexpectedResponse(provider.displayName))
    }
    let transport = transport
    let clock = clock
    let log = log
    return await withTaskGroup(of: ProbeResult?.self) { group in
      group.addTask { await adapter.probe(key: key, transport: transport) }
      group.addTask {
        do {
          try await clock.sleep(for: Self.probeTimeout)
        } catch {
          return nil   // Cancelled because the probe finished first.
        }
        log.emit(.error, .pollFailed, cat: .poll(provider.rawValue), msg: "probe timed out", acct: provider.rawValue,
                 job: "probe", ctx: ["attempts": 1, "timeout_s": 10])
        return Self.failed(CoreStrings.unreachable(provider.displayName))
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first ?? Self.failed(CoreStrings.unreachable(provider.displayName))
    }
  }

  static func failed(_ message: String) -> ProbeResult {
    ProbeResult(
      capabilities: Capabilities(usage: false, cost: false, balance: false, perKeyUsage: false, keyNames: false,
                                 balanceModeDefault: .spendOnly, usageLag: .zero, currencyHint: .usd),
      humanMessage: message, currency: .usd
    )
  }

  // MARK: - Create, replace, test, remove

  /// After a passed probe (R8: the key goes to the Keychain in the same flow that validated it): the Keychain
  /// item (`ref` = provider), the `account` row with its four `poll_state` rows (03), and the discovered keys.
  /// If the database refuses the account, the Keychain item is deleted again and the error is rethrown.
  public func create(_ provider: ProviderID, label: String, key: String, probe: ProbeResult) async throws
    -> AccountRecord {
    let time = now()
    let account = AccountRecord(
      id: UUIDv7.make(at: time), provider: provider.rawValue, label: Self.label(label, provider: provider),
      keychainRef: provider.rawValue, balanceMode: probe.capabilities.balanceModeDefault.rawValue,
      currency: probe.currency.rawValue, capabilities: try probe.capabilities.json(), orgId: probe.orgID,
      orgName: probe.orgName, autoReloadEnabled: false, autoReloadToCents: nil, autoReloadBelowCents: nil,
      paused: false, intervalOverrideJson: nil, createdAt: DBTime.string(time)
    )
    try await keyStore.set(account.keychainRef, secret: ProviderID.normalizedKey(key))
    var inserted = false
    do {
      try await repository.insertAccount(account)
      inserted = true
      try await repository.upsertProviderKeys(accountID: account.id, keys: probe.discoveredKeys, seenAt: time)
    } catch {
      // Undo in reverse order; the caller logs `error` (`ui.error`) and shows it.
      if inserted { try await repository.deleteAccount(id: account.id) }
      try await keyStore.delete(account.keychainRef)
      throw error
    }
    return account
  }

  /// The label the user typed, or the provider's name when it is blank (08: default provider name).
  static func label(_ typed: String, provider: ProviderID) -> String {
    let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? provider.displayName : trimmed
  }

  /// `Replace key…` after its probe passed: the new key replaces the item, the circuit resets, discovered keys are
  /// refreshed.
  public func replaceKey(_ account: AccountRecord, key: String, probe: ProbeResult) async throws {
    try await keyStore.set(account.keychainRef, secret: ProviderID.normalizedKey(key))
    try await resetCircuit(account)
    try await repository.upsertProviderKeys(accountID: account.id, keys: probe.discoveredKeys, seenAt: now())
  }

  /// `Test`: probes with the stored key; a passed probe resets the circuit (04).
  public func test(_ account: AccountRecord) async -> ProbeResult {
    guard let provider = ProviderID(rawValue: account.provider) else {
      return Self.failed(CoreStrings.unexpectedResponse(account.provider))
    }
    let key: String
    do {
      guard let stored = try await keyStore.get(account.keychainRef) else {
        log.emit(.error, .keychainMissing, cat: .keychain, msg: "no Keychain item for the account",
                 acct: account.keychainRef)
        return Self.failed(CoreStrings.keyMissing)
      }
      key = stored
    } catch {
      return Self.failed(CoreStrings.keyMissing)   // `KeychainKeyStore` has logged the failure.
    }
    let redactor = log.redactor
    redactor.register(secret: key)
    defer { redactor.unregister(secret: key) }
    let result = await probe(provider, key: key)
    if result.humanMessage == nil {
      do {
        try await resetCircuit(account)
      } catch {
        log.emit(.error, .uiError, cat: .ui, msg: "circuit not reset", acct: account.provider, err: error,
                 ctx: ["view": "settings.accounts"])
      }
    }
    return result
  }

  func resetCircuit(_ account: AccountRecord) async throws {
    for job in try await repository.resetCircuit(accountID: account.id) {
      log.emit(.info, .pollCircuitClose, cat: .poll(account.provider), msg: "circuit closed by a key test",
               acct: account.provider, job: job.rawValue, ctx: ["until": .null])
    }
  }

  /// `Remove account…` (09 § Reset semantics): the `account` row and, by cascade, everything that belongs to it;
  /// the Keychain item; the provider's templated settings.
  @MainActor
  public func remove(_ account: AccountRecord, settings: Settings) async throws {
    try await repository.deleteAccount(id: account.id)
    try await keyStore.delete(account.keychainRef)
    if let provider = ProviderID(rawValue: account.provider) { settings.removeProviderKeys(provider) }
  }

  // MARK: - Anchor, startup

  /// Onboarding step 3's anchor amount (08): `ledger_event(kind=anchor, source=user)`, logged `ledger.anchor_set`.
  /// The ledger math that uses it lands in 5.3.
  public func setAnchor(_ account: AccountRecord, cents: Int64) async throws {
    let time = now()
    try await repository.insertLedgerEvent(LedgerEventRecord(
      id: UUIDv7.make(at: time), accountId: account.id, ts: DBTime.string(time), kind: "anchor", amountCents: cents,
      currency: account.currency, note: nil, source: "user"
    ))
    log.emit(.info, .ledgerAnchorSet, cat: .ledger, msg: "anchor set", acct: account.provider,
             ctx: ["amount_cents": .int(Int(cents)), "source": "user"])
  }

  /// 04 startup step 3: which accounts have no Keychain item. Each missing one logs `keychain.missing`. A Keychain
  /// that cannot be read (locked, denied) is not "missing": `KeychainKeyStore` logs it, and the card stays as is.
  public func missingKeys(_ accounts: [AccountRecord]) async -> Set<String> {
    var missing: Set<String> = []
    for account in accounts {
      do {
        guard !(try await keyStore.contains(account.keychainRef)) else { continue }
        missing.insert(account.keychainRef)
        log.emit(.error, .keychainMissing, cat: .keychain, msg: "no Keychain item for the account",
                 acct: account.keychainRef)
      } catch {
        // `KeychainKeyStore` logged `keychain.read_failed` / `access_denied`; unreadable is not missing.
        continue
      }
    }
    return missing
  }
}
