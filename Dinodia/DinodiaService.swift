import Foundation

enum DinodiaServiceError: LocalizedError {
    case userNotFound
    case connectionMissing(String)

    var errorDescription: String? {
        switch self {
        case .userNotFound:
            return "User not found"
        case .connectionMissing(let message):
            return message
        }
    }
}

enum DinodiaService {
    static func fetchUserWithRelations(userId: Int) async throws -> UserWithRelations {
        let users: [UserSummary] = try await SupabaseREST.get(
            "User",
            filters: [URLQueryItem(name: "id", value: "eq.\(userId)")],
            select: "id,username,role,haConnectionId",
            limit: 1
        )
        guard let user = users.first else {
            throw DinodiaServiceError.userNotFound
        }
        let accessRules: [AccessRule] = try await SupabaseREST.get(
            "AccessRule",
            filters: [URLQueryItem(name: "userId", value: "eq.\(userId)")]
        )
        return UserWithRelations(summary: user, accessRules: accessRules)
    }

    static func fetchHaConnection(byId id: Int) async throws -> HaConnection? {
        let connections: [HaConnection] = try await SupabaseREST.get(
            "HaConnection",
            filters: [URLQueryItem(name: "id", value: "eq.\(id)")],
            select: "*",
            limit: 1
        )
        return connections.first
    }

    static func fetchHaConnectionOwned(by userId: Int) async throws -> HaConnection? {
        let connections: [HaConnection] = try await SupabaseREST.get(
            "HaConnection",
            filters: [URLQueryItem(name: "ownerId", value: "eq.\(userId)")],
            select: "*",
            limit: 1
        )
        return connections.first
    }

    static func getUserWithHaConnection(userId: Int) async throws -> (UserWithRelations, HaConnection) {
        var relations = try await fetchUserWithRelations(userId: userId)
        var haConnection: HaConnection? = nil

        if let connectionId = relations.summary.haConnectionId {
            haConnection = try await fetchHaConnection(byId: connectionId)
        }

        if haConnection == nil, relations.summary.role == .ADMIN {
            haConnection = try await fetchHaConnectionOwned(by: relations.summary.id)
        }

        if relations.summary.role == .TENANT {
            // Resolve canonical connection from an admin
            let admins: [UserSummary] = try await SupabaseREST.get(
                "User",
                filters: [URLQueryItem(name: "role", value: "eq.ADMIN")],
                select: "id,username,role,haConnectionId",
                limit: 1
            )
            if let admin = admins.first {
                var adminConnection: HaConnection? = nil
                if let adminHaId = admin.haConnectionId {
                    adminConnection = try await fetchHaConnection(byId: adminHaId)
                }
                if adminConnection == nil {
                    adminConnection = try await fetchHaConnectionOwned(by: admin.id)
                }

                if let adminConnection {
                    // Update tenant's haConnectionId to match admin's
                    let updatePayload = ["haConnectionId": adminConnection.id]
                    _ = try await SupabaseREST.update(
                        "User",
                        filters: [URLQueryItem(name: "id", value: "eq.\(relations.summary.id)")],
                        payload: updatePayload
                    ) as UserSummary
                    relations = try await fetchUserWithRelations(userId: relations.summary.id)
                    haConnection = adminConnection
                    if admin.haConnectionId == nil {
                        // ensure admin row stored id as well
                        let adminUpdate = ["haConnectionId": adminConnection.id]
                        _ = try await SupabaseREST.update(
                            "User",
                            filters: [URLQueryItem(name: "id", value: "eq.\(admin.id)")],
                            payload: adminUpdate
                        ) as UserSummary
                    }
                }
            }
        }

        guard let resolvedConnection = haConnection else {
            throw DinodiaServiceError.connectionMissing("Dinodia Hub connection is not configured for this home.")
        }

        return (relations, resolvedConnection)
    }

    static func fetchDevicesForUser(userId: Int, mode: HaMode) async throws -> [UIDevice] {
        let (relations, haConnection) = try await getUserWithHaConnection(userId: userId)
        let rawUrl = (mode == .cloud ? haConnection.cloudUrl : haConnection.baseUrl) ?? ""
        let baseUrl = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !baseUrl.isEmpty else {
            return []
        }

        let haLike = HaConnectionLike(baseUrl: baseUrl, longLivedToken: haConnection.longLivedToken)
        let reachable = await HAService.probeHaReachability(haLike, timeout: mode == .home ? 2.0 : 4.0)
        if !reachable {
            if mode == .home {
                throw DinodiaServiceError.connectionMissing(
                    "We cannot find your Dinodia Hub on the home Wi-Fi. It looks like you are away from home—switch to Dinodia Cloud to control your place."
                )
            } else {
                throw DinodiaServiceError.connectionMissing(
                    "Dinodia Cloud is not ready yet. The homeowner needs to finish setting up remote access for this property."
                )
            }
        }

        var enrichedDevices: [EnrichedDevice] = []
        do {
            enrichedDevices = try await HAService.getDevicesWithMetadata(haLike)
        } catch {
            throw error
        }

        let overrides: [DeviceOverride] = try await SupabaseREST.get(
            "Device",
            filters: [URLQueryItem(name: "haConnectionId", value: "eq.\(haConnection.id)")]
        )
        let overrideMap = Dictionary(uniqueKeysWithValues: overrides.map { ($0.entityId, $0) })

        let devices: [UIDevice] = enrichedDevices.map { device in
            let override = overrideMap[device.entityId]
            let name = override?.name ?? device.name
            let areaName = override?.area ?? device.areaName
            let labels: [String] = {
                if let overrideLabel = override?.label, !overrideLabel.isEmpty {
                    return [overrideLabel]
                }
                return device.labels
            }()
            let labelCategory = classifyDeviceByLabel(labels) ?? device.labelCategory
            let primaryLabel = override?.label ?? labels.first ?? labelCategory
            return UIDevice(
                entityId: device.entityId,
                deviceId: device.deviceId,
                name: name,
                state: device.state,
                area: areaName,
                areaName: areaName,
                label: primaryLabel,
                labelCategory: labelCategory,
                labels: labels,
                domain: device.domain,
                attributes: device.attributes
            )
        }

        if relations.summary.role == .TENANT {
            let allowedAreas = Set(relations.accessRules.map { $0.area })
            return devices.filter { device in
                guard let areaName = device.areaName else { return false }
                return allowedAreas.contains(areaName)
            }
        }

        return devices
    }

    struct UpdateHaSettingsParams {
        let adminId: Int
        let haUsername: String
        let haBaseUrl: String
        let haCloudUrl: String?
        let haPassword: String?
        let haLongLivedToken: String?
    }

    static func updateHaSettings(_ params: UpdateHaSettingsParams) async throws -> HaConnection {
        let (_, connection) = try await getUserWithHaConnection(userId: params.adminId)
        let normalizedBase = try normalizeHaBaseUrl(params.haBaseUrl)

        var update: [String: Any] = [
            "haUsername": params.haUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            "baseUrl": normalizedBase,
        ]

        if let cloud = params.haCloudUrl {
            let trimmed = cloud.trimmingCharacters(in: .whitespacesAndNewlines)
            update["cloudUrl"] = trimmed.isEmpty ? NSNull() : trimmed
        }
        if let password = params.haPassword, !password.isEmpty {
            update["haPassword"] = password
        }
        if let token = params.haLongLivedToken, !token.isEmpty {
            update["longLivedToken"] = token
        }

        let body = try JSONSerialization.data(withJSONObject: update, options: [])
        var filters = [URLQueryItem(name: "id", value: "eq.\(connection.id)")]
        filters.append(URLQueryItem(name: "select", value: "*"))
        let updated: HaConnection = try await SupabaseREST.updateRaw("HaConnection", filters: filters, body: body)
        return updated
    }

    private static func normalizeHaBaseUrl(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw DinodiaServiceError.connectionMissing("Dinodia Hub URL must start with http:// or https://")
        }
        var cleaned = trimmed
        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }
        return cleaned
    }
}
