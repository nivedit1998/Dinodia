import Foundation

enum SupabaseRESTError: LocalizedError {
    case invalidResponse
    case decodingFailed

    var errorDescription: String? {
        "We could not reach Dinodia right now. Please try again."
    }
}

enum SupabaseREST {
    private static let base = EnvConfig.supabaseURL.appendingPathComponent("rest/v1")

    private static func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw SupabaseRESTError.invalidResponse
        }
        return url
    }

    private static func makeRequest(path: String, method: String, queryItems: [URLQueryItem], body: Data? = nil, prefer: String? = nil) throws -> URLRequest {
        let url = try makeURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(EnvConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(EnvConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        request.httpBody = body
        return request
    }

    static func get<T: Decodable>(_ table: String, filters: [URLQueryItem], select: String = "*", limit: Int? = nil) async throws -> [T] {
        var query = filters
        query.append(URLQueryItem(name: "select", value: select))
        if let limit {
            query.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        let request = try makeRequest(path: table, method: "GET", queryItems: query)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SupabaseRESTError.invalidResponse
        }
        return try JSONDecoder().decode([T].self, from: data)
    }

    static func upsert<T: Decodable>(_ table: String, payload: Encodable) async throws -> T {
        let data = try JSONEncoder().encode(payload)
        return try await upsertRaw(table, body: data) as T
    }

    static func upsertRaw<T: Decodable>(_ table: String, body: Data) async throws -> T {
        let request = try makeRequest(
            path: table,
            method: "POST",
            queryItems: [],
            body: body,
            prefer: "return=representation"
        )
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseRESTError.invalidResponse
        }
        let items = try JSONDecoder().decode([T].self, from: responseData)
        guard let item = items.first else { throw SupabaseRESTError.invalidResponse }
        return item
    }

    static func update<T: Decodable>(_ table: String, filters: [URLQueryItem], payload: Encodable) async throws -> T {
        var query = filters
        query.append(URLQueryItem(name: "select", value: "*"))
        let data = try JSONEncoder().encode(payload)
        return try await updateRaw(table, filters: query, body: data) as T
    }

    static func updateRaw<T: Decodable>(_ table: String, filters: [URLQueryItem], body: Data) async throws -> T {
        let request = try makeRequest(path: table, method: "PATCH", queryItems: filters, body: body, prefer: "return=representation")
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseRESTError.invalidResponse
        }
        let items = try JSONDecoder().decode([T].self, from: responseData)
        guard let item = items.first else { throw SupabaseRESTError.invalidResponse }
        return item
    }
}
