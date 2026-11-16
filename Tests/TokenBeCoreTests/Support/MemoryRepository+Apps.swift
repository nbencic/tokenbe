import Foundation
@testable import TokenBeCore

/// `MemoryRepository`'s apps (7.1) and ingest (7.2) aggregates: plain storage, enough for code above the store.
extension MemoryRepository {
  func upsertApp(displayName: String, binding: ProviderKeyRef?) async throws -> AppRecord {
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = AppSlug.make(trimmed, taken: Set(apps.map(\.name)))
    let app = AppRecord(id: UUIDv7.make(), name: name, displayName: trimmed.isEmpty ? name : trimmed,
                        createdAt: DBTime.string(Date()), isAuto: false)
    apps.append(app)
    if let binding { try await bind(appID: app.id, key: binding) }
    return app
  }

  func upsertApp(id: String, displayName: String) async throws {
    guard id != Attribution.unassignedID, let index = apps.firstIndex(where: { $0.id == id }) else {
      throw StoreError.notFound(id)
    }
    apps[index].displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func fetchApps() async throws -> [AppRecord] { apps.sorted { ($0.displayName, $0.name) < ($1.displayName, $1.name) } }

  func bind(appID: String, key: ProviderKeyRef) async throws {
    try await unbind(key: key)
    bindings.append(AppBindingRecord(appId: appID, accountId: key.accountID, kind: "provider_key",
                                     value: key.providerKeyID))
  }

  func unbind(key: ProviderKeyRef) async throws {
    bindings.removeAll { $0.accountId == key.accountID && $0.kind == "provider_key" && $0.value == key.providerKeyID }
  }

  func fetchBindings() async throws -> [AppBindingRecord] { bindings }

  func loadIngestFiles() async throws -> [IngestFileRecord] { ingestFiles.values.sorted { $0.path < $1.path } }

  func applyIngestBatch(_ batch: IngestBatch) async throws -> IngestBatchResult {
    var result = IngestBatchResult()
    for item in batch.lines {
      if eventKeys.insert("\(item.line.provider.rawValue)/\(item.line.requestID)").inserted {
        result.inserted += 1
      } else {
        result.duplicates.append(item.line.requestID)
      }
    }
    var file = batch.file
    let prior = batch.resetCounters ? nil : ingestFiles[file.path]
    file.linesOk = (prior?.linesOk ?? 0) + Int64(result.inserted)
    file.linesBad = (prior?.linesBad ?? 0) + batch.rejected
    file.linesDup = (prior?.linesDup ?? 0) + Int64(result.duplicates.count)
    ingestFiles[file.path] = file
    return result
  }
}
