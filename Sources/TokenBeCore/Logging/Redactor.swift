import Foundation
import Synchronization

/// Removes secrets from every string before it reaches a sink (07 § Redaction, 12 § R8).
/// Patterns 1–6 run in order, then the exact pass over secrets registered while they are in flight.
public final class Redactor: Sendable {
  public static let keyMarker = "«redacted:key»"
  public static let headerMarker = "«redacted:header»"
  public static let tokenMarker = "«redacted:token»"

  /// Registered secrets with a reference count, so overlapping requests with the same key stay redacted.
  private let secrets = Mutex<[String: Int]>([:])

  public init() {}

  /// Registers a secret for the exact pass. Call `unregister(secret:)` once the secret is dropped (R8).
  public func register(secret: String) {
    guard !secret.isEmpty else { return }
    secrets.withLock { $0[secret, default: 0] += 1 }
  }

  public func unregister(secret: String) {
    secrets.withLock { held in
      guard let count = held[secret] else { return }
      if count <= 1 { held[secret] = nil } else { held[secret] = count - 1 }
    }
  }

  public func redact(_ input: String) -> String {
    var text = input
    // 1. OpenAI / DeepSeek style keys.
    text.replace(/sk-[A-Za-z0-9_\-]{8,}/) { _ in Redactor.keyMarker }
    // 2. Anthropic keys (already covered by 1; kept so the order of 07 holds if 1 ever narrows).
    text.replace(/sk-ant-[A-Za-z0-9_\-]{8,}/) { _ in Redactor.keyMarker }
    // 3. Auth headers, optional scheme word and JSON quotes included (Q-006).
    text.replace(/(?i)(authorization|x-api-key|x-goog-api-key)(["']?)\s*[:=]\s*(["']?)(?:[A-Za-z]+\s+)?[^\s"',}]+/) { match in
      "\(match.output.1)\(match.output.2): \(match.output.3)\(Redactor.headerMarker)"
    }
    // 4. Bearer tokens, including `+ / =` (Q-006).
    text.replace(/(?i)bearer\s+[^\s"',}]{8,}/) { _ in "Bearer \(Redactor.tokenMarker)" }
    // 5. xAI keys.
    text.replace(/xai-[A-Za-z0-9]{8,}/) { _ in Redactor.keyMarker }
    // 6. OpenRouter keys.
    text.replace(/sk-or-v1-[A-Za-z0-9]{8,}/) { _ in Redactor.keyMarker }
    // 7. Exact pass, longest first so a secret that contains another is removed whole.
    let held = secrets.withLock { Array($0.keys) }.sorted { $0.count > $1.count }
    for secret in held where text.contains(secret) {
      text = text.replacingOccurrences(of: secret, with: Redactor.keyMarker)
    }
    return text
  }
}
