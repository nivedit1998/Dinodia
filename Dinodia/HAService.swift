import Foundation

struct HAState: Codable {
    let entity_id: String
    let state: String
    let attributes: [String: CodableValue]
}

struct TemplateDeviceMeta: Codable {
    let entity_id: String
    let area_name: String?
    let labels: [String]?
    let device_id: String?
}

struct EnrichedDevice: Codable {
    let entityId: String
    let name: String
    let state: String
    let areaName: String?
    let labels: [String]
    let labelCategory: String?
    let domain: String
    let attributes: [String: CodableValue]
    let deviceId: String?
}

enum HAServiceError: LocalizedError {
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .network(let message):
            return message
        case .server(let message):
            return message
        }
    }
}

enum HAService {
    private static func buildURL(base: String, path: String) -> URL? {
        if path.hasPrefix("/") {
            return URL(string: base + path)
        }
        return URL(string: base)?.appendingPathComponent(path)
    }

    private static func describeNetworkFailure(base: String, error: Error) -> HAServiceError {
        var hints: [String] = []
        if let url = URL(string: base) {
            let host = url.host?.lowercased() ?? ""
            if host.hasSuffix(".local") {
                hints.append("Android/iOS devices often cannot resolve .local hostnames. Update the Dinodia Hub URL to use the IP address (e.g., http://192.168.1.10:8123) in Settings.")
            }
            if url.scheme == "http" {
                hints.append("Make sure you are on the same Wi-Fi as the Dinodia Hub and that cleartext HTTP traffic is allowed.")
            }
        }
        let hintText = hints.isEmpty ? "" : " " + hints.joined(separator: " ")
        return .network("Dinodia Hub network issue: \(error.localizedDescription).\(hintText) Please try again.")
    }

    private static func makeRequest(ha: HaConnectionLike, path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 5.0) throws -> URLRequest {
        guard let url = buildURL(base: ha.baseUrl, path: path) else {
            throw HAServiceError.server("Invalid Dinodia Hub URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(ha.longLivedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = timeout
        return request
    }

    static func callAPI<T: Decodable>(_ ha: HaConnectionLike, path: String, timeout: TimeInterval = 5.0) async throws -> T {
        let request = try makeRequest(ha: ha, path: path, timeout: timeout)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw HAServiceError.server("Dinodia Hub could not complete that request (\((response as? HTTPURLResponse)?.statusCode ?? 0)). \(text.isEmpty ? "Please try again." : text)")
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw describeNetworkFailure(base: ha.baseUrl, error: error)
        }
    }

    static func renderTemplate<T: Decodable>(_ ha: HaConnectionLike, template: String, timeout: TimeInterval = 5.0) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: ["template": template])
        let request = try makeRequest(ha: ha, path: "/api/template", method: "POST", body: body, timeout: timeout)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw HAServiceError.server("Dinodia Hub could not prepare that data (\((response as? HTTPURLResponse)?.statusCode ?? 0)). \(text.isEmpty ? "Please try again." : text)")
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw describeNetworkFailure(base: ha.baseUrl, error: error)
        }
    }

    static func getDevicesWithMetadata(_ ha: HaConnectionLike) async throws -> [EnrichedDevice] {
        let states: [HAState] = try await callAPI(ha, path: "/api/states")
        let template = """
        {% set ns = namespace(result=[]) %}
        {% for s in states %}
          {% set item = {
            "entity_id": s.entity_id,
            "area_name": area_name(s.entity_id),
            "device_id": device_id(s.entity_id),
            "labels": (labels(s.entity_id) | map('label_name') | list)
          } %}
          {% set ns.result = ns.result + [item] %}
        {% endfor %}
        {{ ns.result | tojson }}
        """
        let meta: [TemplateDeviceMeta] = (try? await renderTemplate(ha, template: template)) ?? []
        let metaByEntity = Dictionary(uniqueKeysWithValues: meta.map { ($0.entity_id, $0) })

        return states.map { state in
            let domain = state.entity_id.split(separator: ".").first.map(String.init) ?? ""
            let metaEntry = metaByEntity[state.entity_id]
            let deviceId = metaEntry?.device_id?.isEmpty == false ? metaEntry?.device_id : nil
            let labels = (metaEntry?.labels ?? []).filter { !$0.isEmpty }
            let labelCategory = classifyDeviceByLabel(labels) ?? classifyDeviceByLabel([domain])
            return EnrichedDevice(
                entityId: state.entity_id,
                name: (state.attributes["friendly_name"]?.anyValue as? String) ?? state.entity_id,
                state: state.state,
                areaName: metaEntry?.area_name,
                labels: labels,
                labelCategory: labelCategory,
                domain: domain,
                attributes: state.attributes,
                deviceId: deviceId
            )
        }
    }

    static func callHaService(_ ha: HaConnectionLike, domain: String, service: String, data: [String: Any], timeout: TimeInterval = 5.0) async throws {
        let body = try JSONSerialization.data(withJSONObject: data)
        let request = try makeRequest(ha: ha, path: "/api/services/\(domain)/\(service)", method: "POST", body: body, timeout: timeout)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw HAServiceError.server("Dinodia Hub could not apply that action (\((response as? HTTPURLResponse)?.statusCode ?? 0)). Please try again.")
            }
        } catch {
            throw describeNetworkFailure(base: ha.baseUrl, error: error)
        }
    }

    static func probeHaReachability(_ ha: HaConnectionLike, timeout: TimeInterval = 2.0) async -> Bool {
        do {
            let request = try makeRequest(ha: ha, path: "/api/", timeout: timeout)
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode ?? 0 > 0
        } catch {
            return false
        }
    }

    static func fetchState(_ ha: HaConnectionLike, entityId: String) async throws -> HAState {
        try await callAPI(ha, path: "/api/states/\(entityId)")
    }
}
