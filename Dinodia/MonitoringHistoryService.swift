import Foundation

private struct MonitoringReading: Decodable {
    let entityId: String
    let haConnectionId: Int
    let capturedAt: String
    let unit: String?
    let numericValue: Double?
}

enum MonitoringHistoryError: LocalizedError {
    case unableToLoad

    var errorDescription: String? {
        "We could not load your history right now. Please try again."
    }
}

enum MonitoringHistoryService {
    private static let defaultDays: [HistoryBucket: Int] = [
        .daily: 30,
        .weekly: 84,
        .monthly: 365,
    ]

    static func fetchHistory(userId: Int, entityId: String, bucket: HistoryBucket) async throws -> HistoryResult {
        let (_, connection) = try await DinodiaService.getUserWithHaConnection(userId: userId)
        let days = defaultDays[bucket] ?? 30
        let fromDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let iso = iso8601String(from: fromDate)

        do {
            let filters = [
                URLQueryItem(name: "haConnectionId", value: "eq.\(connection.id)"),
                URLQueryItem(name: "entityId", value: "eq.\(entityId)"),
                URLQueryItem(name: "capturedAt", value: "gte.\(iso)"),
                URLQueryItem(name: "order", value: "capturedAt"),
            ]
            let readings: [MonitoringReading] = try await SupabaseREST.get("MonitoringReading", filters: filters)
            return aggregate(readings: readings, bucket: bucket)
        } catch {
            if let api = EnvConfig.dinodiaPlatformAPI {
                return try await fetchViaPlatformAPI(baseURL: api, userId: userId, entityId: entityId, bucket: bucket)
            }
            throw error
        }
    }

    private static func fetchViaPlatformAPI(baseURL: URL, userId: Int, entityId: String, bucket: HistoryBucket) async throws -> HistoryResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/admin/monitoring/history"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "userId": userId,
            "entityId": entityId,
            "bucket": bucket.rawValue,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw MonitoringHistoryError.unableToLoad
        }
        if let result = try? JSONDecoder().decode(HistoryResult.self, from: data) {
            return result
        }
        throw MonitoringHistoryError.unableToLoad
    }

    private static func aggregate(readings: [MonitoringReading], bucket: HistoryBucket) -> HistoryResult {
        var unit: String? = nil
        var buckets: [String: (sum: Double, count: Int, label: String, start: Date)] = [:]
        for reading in readings {
            if unit == nil, let readingUnit = reading.unit, !readingUnit.isEmpty {
                unit = readingUnit
            }
            guard let numeric = reading.numericValue else { continue }
            guard let capturedDate = ISO8601DateFormatter().date(from: reading.capturedAt) else { continue }
            let info = bucketInfo(bucket: bucket, capturedAt: capturedDate)
            let existing = buckets[info.key]
            if existing == nil {
                buckets[info.key] = (numeric, 1, info.label, info.start)
            } else {
                buckets[info.key] = (existing!.sum + numeric, existing!.count + 1, info.label, info.start)
            }
        }

        let shouldUseSum = unit?.lowercased().contains("wh") == true
        let points = buckets.values
            .sorted(by: { $0.start < $1.start })
            .map { entry -> HistoryPoint in
                let value = shouldUseSum ? entry.sum : entry.sum / Double(entry.count)
                return HistoryPoint(bucketStart: iso8601String(from: entry.start), label: entry.label, value: value, count: entry.count)
            }

        return HistoryResult(unit: unit, points: points)
    }

    private static func bucketInfo(bucket: HistoryBucket, capturedAt: Date) -> (key: String, label: String, start: Date) {
        switch bucket {
        case .weekly:
            let info = isoWeekInfo(for: capturedAt)
            let label = "Week of \(formatDate(info.weekStart))"
            return ("\(info.year)-W\(String(info.week).pad(with: 2))", label, info.weekStart)
        case .monthly:
            let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: capturedAt)) ?? capturedAt
            return ("\(year(start))-\(String(month(start)).pad(with: 2))", formatMonthLabel(start), start)
        case .daily:
            fallthrough
        default:
            let start = startOfDay(capturedAt)
            return (formatDate(start), formatDate(start), start)
        }
    }

    private static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func year(_ date: Date) -> Int {
        Calendar.current.component(.year, from: date)
    }

    private static func month(_ date: Date) -> Int {
        Calendar.current.component(.month, from: date)
    }

    private static func isoWeekInfo(for date: Date) -> (year: Int, week: Int, weekStart: Date) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        let weekOfYear = calendar.component(.weekOfYear, from: date)
        let yearForWeekOfYear = calendar.component(.yearForWeekOfYear, from: date)
        let startComponents = DateComponents(weekOfYear: weekOfYear, yearForWeekOfYear: yearForWeekOfYear)
        let weekStart = calendar.date(from: startComponents) ?? date
        return (yearForWeekOfYear, weekOfYear, weekStart)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func formatMonthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private extension String {
    func pad(with digits: Int) -> String {
        self.count >= digits ? self : String(repeating: "0", count: max(0, digits - self.count)) + self
    }
}
