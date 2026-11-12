import Foundation
import Network

/// Whether the Mac can reach the network, and over what (D-nwpathmonitor).
public struct NetworkStatus: Sendable, Equatable {
  public var online: Bool
  /// `wifi`, `wired`, `cellular`, `loopback`, `other`, or `none` when no interface is available (Q-026).
  public var interface: String

  public init(online: Bool, interface: String) {
    self.online = online
    self.interface = interface
  }
}

/// Reachability seam (14 § 0.3): `NWPathMonitorAdapter` in the app; the scheduler's test double arrives with its
/// consumer in 4.1, which skips polls while offline (`sched.skip reason=offline`).
public protocol NetworkMonitor: Sendable {
  /// The current status first, then one value per change. Each change after the first logs `app.network_changed`.
  func statuses() -> AsyncStream<NetworkStatus>
}

/// Turns a stream of path snapshots into changes, and logs each transition `app.network_changed {online, interface}`
/// (07). The first status is a starting point, not a transition, so it is yielded but not logged.
struct NetworkTransitions: Sendable {
  let logPipeline: LogPipeline?
  private(set) var last: NetworkStatus?

  init(logPipeline: LogPipeline?) {
    self.logPipeline = logPipeline
  }

  /// True when `status` differs from the previous one (always true for the first).
  mutating func update(_ status: NetworkStatus) -> Bool {
    guard status != last else { return false }
    defer { last = status }
    guard last != nil else { return true }
    let ctx: [String: LogValue] = ["online": .bool(status.online), "interface": .string(status.interface)]
    let msg = status.online ? "network online" : "network offline"
    if let logPipeline {
      logPipeline.emit(.info, .appNetworkChanged, cat: .app, msg: msg, ctx: ctx)
    } else {
      Log.info(.appNetworkChanged, cat: .app, msg: msg, ctx: ctx)
    }
    return true
  }
}

/// `NetworkMonitor` over `NWPathMonitor`, consumed as an `AsyncSequence` (no dispatch queue, R6).
public final class NWPathMonitorAdapter: NetworkMonitor {
  let logPipeline: LogPipeline?

  public init(logPipeline: LogPipeline? = nil) {
    self.logPipeline = logPipeline
  }

  public func statuses() -> AsyncStream<NetworkStatus> {
    let logPipeline = logPipeline
    return AsyncStream { continuation in
      let task = Task {
        // Created inside the task: `NWPathMonitor` is not Sendable, so it never crosses an isolation boundary.
        let monitor = NWPathMonitor()
        var transitions = NetworkTransitions(logPipeline: logPipeline)
        for await path in monitor {
          let status = Self.status(online: path.status == .satisfied, interfaces: path.availableInterfaces.map(\.type))
          if transitions.update(status) { continuation.yield(status) }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  static func status(online: Bool, interfaces: [NWInterface.InterfaceType]) -> NetworkStatus {
    guard let first = interfaces.first else { return NetworkStatus(online: online, interface: "none") }
    let name = switch first {
    case .wifi: "wifi"
    case .wiredEthernet: "wired"
    case .cellular: "cellular"
    case .loopback: "loopback"
    case .other: "other"
    @unknown default: "other"
    }
    return NetworkStatus(online: online, interface: name)
  }
}

#if DEBUG
/// DEBUG UI tests (`TOKENBE_TEST_OFFLINE=1` under a test root, Q-036): a Mac that stays offline, so the Offline
/// state (08) can be tested without touching the runner's network. Like `FixtureTransport`, never in Release.
public struct FixedNetworkMonitor: NetworkMonitor {
  public let status: NetworkStatus

  public init(online: Bool) {
    status = NetworkStatus(online: online, interface: online ? "other" : "none")
  }

  public func statuses() -> AsyncStream<NetworkStatus> {
    let (stream, continuation) = AsyncStream.makeStream(of: NetworkStatus.self)
    continuation.yield(status)
    return stream
  }
}
#endif
