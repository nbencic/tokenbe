import Synchronization

/// The last 500 records of any level (07 § Sinks 3), for the diagnostics bundle and crash records.
public final class Breadcrumbs: Sendable {
  public static let defaultCapacity = 500

  private struct Ring {
    var items: [LogRecord] = []
    var next = 0
  }

  public let capacity: Int
  private let ring = Mutex(Ring())

  public init(capacity: Int = Breadcrumbs.defaultCapacity) {
    self.capacity = max(1, capacity)
  }

  public func append(_ record: LogRecord) {
    ring.withLock { ring in
      if ring.items.count < capacity {
        ring.items.append(record)
      } else {
        ring.items[ring.next] = record
      }
      ring.next = (ring.next + 1) % capacity
    }
  }

  /// Oldest first.
  public func snapshot() -> [LogRecord] {
    ring.withLock { ring in
      guard ring.items.count == capacity else { return ring.items }
      return Array(ring.items[ring.next...] + ring.items[..<ring.next])
    }
  }
}
