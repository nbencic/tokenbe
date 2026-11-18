import Foundation

// xAI Management API bodies (02 § xai). Field names come only from 02 (R2) until H6 records them. Decoding is
// lenient like OpenAI's: a key 02 does not list is collected, not fatal; a missing or malformed required field fails
// as `PollError.decode(field:path:)`.

/// `GET /auth/management-keys/validation`: the management key's metadata. Only the team is read: `scopeId` when
/// `scope` is `SCOPE_TEAM`, else the deprecated `teamId` (02).
struct XAIValidation: Decodable, Equatable {
  var scope: String?
  var scopeId: String?
  var teamId: String?

  /// The team whose billing the key reads; nil when the key names none (an organization-scoped key).
  var team: String? {
    if scope == "SCOPE_TEAM", let scopeId, !scopeId.isEmpty { return scopeId }
    if let teamId, !teamId.isEmpty { return teamId }
    return nil
  }

  enum CodingKeys: String, CodingKey, CaseIterable {
    case apiKeyId, teamId, scope, scopeId, ownerUserId, createTime, modifyTime, name, acls, apiKey, redactedApiKey
    case ipRanges
    /// The docs' example spells `redactedApiKey` this way (02).
    case reactedApiKey
  }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    scope = try container.decodeIfPresent(String.self, forKey: .scope)
    scopeId = try container.decodeIfPresent(String.self, forKey: .scopeId)
    teamId = try container.decodeIfPresent(String.self, forKey: .teamId)
  }
}

/// `POST /v1/billing/teams/{team_id}/usage` → `{ "timeSeries": [ … ], "limitReached": bool }`.
struct XAIUsage: Decodable, Equatable {
  var timeSeries: [XAISeries]
  var limitReached: Bool

  enum CodingKeys: String, CodingKey, CaseIterable {
    case timeSeries, limitReached
  }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    timeSeries = try container.decodeIfPresent([XAISeries].self, forKey: .timeSeries) ?? []
    limitReached = try container.decodeIfPresent(Bool.self, forKey: .limitReached) ?? false
  }
}

/// One group (grouped by `description`, the model): its data points, one per day.
struct XAISeries: Decodable, Equatable {
  var group: [String]
  var dataPoints: [XAIDataPoint]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case group, groupLabels, dataPoints
  }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    group = try container.decode([String].self, forKey: .group)
    dataPoints = try container.decode([XAIDataPoint].self, forKey: .dataPoints)
  }
}

/// `timestamp` is the bucket's start in UTC (`2025-10-01T00:00:00Z`); `values` holds one number per requested value,
/// here `usd` (US dollars, a JSON number).
struct XAIDataPoint: Decodable, Equatable {
  var timestamp: String
  var values: [Decimal]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case timestamp, values
  }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    timestamp = try container.decode(String.self, forKey: .timestamp)
    values = try container.decode([Decimal].self, forKey: .values)
  }
}

/// The request body of the usage call (02): daily USD per model over `[start, end)`, UTC.
struct XAIUsageRequest: Encodable, Equatable {
  struct TimeRange: Encodable, Equatable {
    var startTime: String
    var endTime: String
    var timezone = "Etc/GMT"
  }

  struct Value: Encodable, Equatable {
    var name = "usd"
    var aggregation = "AGGREGATION_SUM"
  }

  struct Analytics: Encodable, Equatable {
    var timeRange: TimeRange
    var timeUnit = "TIME_UNIT_DAY"
    var values = [Value()]
    var groupBy = ["description"]
    var filters: [String] = []
  }

  var analyticsRequest: Analytics

  /// Whole UTC days: from `start`'s day through the day after `end` (exclusive), as `YYYY-MM-DD 00:00:00`.
  init(start: Date, end: Date) {
    let from = DailyOnce.utcDay(start)
    let through = DailyOnce.utcDay(end.addingTimeInterval(86400))
    analyticsRequest = Analytics(timeRange: TimeRange(startTime: "\(from) 00:00:00", endTime: "\(through) 00:00:00"))
  }

  /// The body, keys sorted so a request is byte-stable (tests compare it).
  func json() throws(PollError) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    // Plain strings and arrays always encode; the catch only satisfies the typed throw (R5: no `try?`).
    do { return try encoder.encode(self) } catch { throw .providerRule("xai_usage_request_unencodable") }
  }
}
