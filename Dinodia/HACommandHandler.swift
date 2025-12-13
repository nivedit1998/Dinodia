import Foundation

enum DeviceCommand: String {
    case lightToggle = "light/toggle"
    case lightSetBrightness = "light/set_brightness"
    case blindOpen = "blind/open"
    case blindClose = "blind/close"
    case mediaPlayPause = "media/play_pause"
    case mediaNext = "media/next"
    case mediaPrevious = "media/previous"
    case mediaVolumeUp = "media/volume_up"
    case mediaVolumeDown = "media/volume_down"
    case mediaVolumeSet = "media/volume_set"
    case boilerTempUp = "boiler/temp_up"
    case boilerTempDown = "boiler/temp_down"
    case tvTogglePower = "tv/toggle_power"
    case speakerTogglePower = "speaker/toggle_power"
}

enum HACommandError: LocalizedError {
    case invalidValue
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidValue:
            return "Command requires numeric value"
        case .unsupported(let command):
            return "Unsupported command \(command)"
        }
    }
}

struct HACommandHandler {
    static func handle(ha: HaConnectionLike, entityId: String, command: DeviceCommand, value: Double? = nil) async throws {
        switch command {
        case .lightToggle:
            try await toggleLight(ha: ha, entityId: entityId)
        case .lightSetBrightness:
            guard let value else { throw HACommandError.invalidValue }
            try await setBrightness(ha: ha, entityId: entityId, value: value)
        case .blindOpen:
            try await HAService.callHaService(ha, domain: "cover", service: "open_cover", data: ["entity_id": entityId])
        case .blindClose:
            try await HAService.callHaService(ha, domain: "cover", service: "close_cover", data: ["entity_id": entityId])
        case .mediaPlayPause:
            try await toggleMedia(ha: ha, entityId: entityId)
        case .mediaNext:
            try await HAService.callHaService(ha, domain: "media_player", service: "media_next_track", data: ["entity_id": entityId])
        case .mediaPrevious:
            try await HAService.callHaService(ha, domain: "media_player", service: "media_previous_track", data: ["entity_id": entityId])
        case .mediaVolumeUp:
            try await HAService.callHaService(ha, domain: "media_player", service: "volume_up", data: ["entity_id": entityId])
        case .mediaVolumeDown:
            try await HAService.callHaService(ha, domain: "media_player", service: "volume_down", data: ["entity_id": entityId])
        case .mediaVolumeSet:
            guard let value else { throw HACommandError.invalidValue }
            try await HAService.callHaService(ha, domain: "media_player", service: "volume_set", data: [
                "entity_id": entityId,
                "volume_level": max(0, min(1, value / 100))
            ])
        case .boilerTempUp, .boilerTempDown:
            try await adjustBoiler(ha: ha, entityId: entityId, increase: command == .boilerTempUp)
        case .tvTogglePower, .speakerTogglePower:
            try await toggleMediaPower(ha: ha, entityId: entityId)
        }
    }

    private static func toggleLight(ha: HaConnectionLike, entityId: String) async throws {
        let state = try await HAService.fetchState(ha, entityId: entityId)
        let domain = entityId.split(separator: ".").first.map(String.init) ?? ""
        if domain == "light" {
            let service = state.state.lowercased() == "on" ? "turn_off" : "turn_on"
            try await HAService.callHaService(ha, domain: "light", service: service, data: ["entity_id": entityId])
        } else {
            try await HAService.callHaService(ha, domain: "homeassistant", service: "toggle", data: ["entity_id": entityId])
        }
    }

    private static func setBrightness(ha: HaConnectionLike, entityId: String, value: Double) async throws {
        let clamped = max(0, min(100, value))
        let domain = entityId.split(separator: ".").first.map(String.init) ?? ""
        guard domain == "light" else {
            throw HACommandError.unsupported("Brightness supported only for lights")
        }
        try await HAService.callHaService(ha, domain: "light", service: "turn_on", data: [
            "entity_id": entityId,
            "brightness_pct": clamped
        ])
    }

    private static func toggleMedia(ha: HaConnectionLike, entityId: String) async throws {
        let state = try await HAService.fetchState(ha, entityId: entityId)
        let isPlaying = state.state.lowercased() == "playing"
        try await HAService.callHaService(ha, domain: "media_player", service: isPlaying ? "media_pause" : "media_play", data: ["entity_id": entityId])
    }

    private static func toggleMediaPower(ha: HaConnectionLike, entityId: String) async throws {
        let state = try await HAService.fetchState(ha, entityId: entityId)
        let isOff = state.state.lowercased() == "off" || state.state.lowercased() == "standby"
        try await HAService.callHaService(ha, domain: "media_player", service: isOff ? "turn_on" : "turn_off", data: ["entity_id": entityId])
    }

    private static func adjustBoiler(ha: HaConnectionLike, entityId: String, increase: Bool) async throws {
        let state = try await HAService.fetchState(ha, entityId: entityId)
        let attrs = state.attributes
        let current = (attrs["temperature"]?.anyValue as? Double)
            ?? (attrs["current_temperature"]?.anyValue as? Double)
            ?? 20
        let next = increase ? current + 1 : current - 1
        try await HAService.callHaService(ha, domain: "climate", service: "set_temperature", data: [
            "entity_id": entityId,
            "temperature": next
        ])
    }
}
