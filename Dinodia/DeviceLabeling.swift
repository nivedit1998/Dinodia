import Foundation

enum LabelCategory: String {
    case light = "Light"
    case blind = "Blind"
    case tv = "TV"
    case speaker = "Speaker"
    case boiler = "Boiler"
    case security = "Security"
    case spotify = "Spotify"
    case `switch` = "Switch"
    case thermostat = "Thermostat"
    case media = "Media"
    case motionSensor = "Motion Sensor"
    case sensor = "Sensor"
    case vacuum = "Vacuum"
    case camera = "Camera"
    case other = "Other"
}

private let LABEL_MAP: [String: LabelCategory] = [
    "light": .light,
    "lights": .light,
    "blind": .blind,
    "blinds": .blind,
    "shade": .blind,
    "shades": .blind,
    "tv": .tv,
    "television": .tv,
    "speaker": .speaker,
    "speakers": .speaker,
    "audio": .speaker,
    "boiler": .boiler,
    "heating": .boiler,
    "thermostat": .thermostat,
    "doorbell": .security,
    "security": .security,
    "home security": .security,
    "spotify": .spotify,
    "switch": .switch,
    "switches": .switch,
    "media": .media,
    "media player": .media,
    "motion": .motionSensor,
    "motion sensor": .motionSensor,
    "sensor": .sensor,
    "vacuum": .vacuum,
    "camera": .camera,
]

let LABEL_ORDER: [String] = [
    "Light",
    "Blind",
    "Motion Sensor",
    "Spotify",
    "Boiler",
    "Doorbell",
    "Home Security",
    "TV",
    "Speaker",
]

let OTHER_LABEL = "Other"
private let labelOrderLower = LABEL_ORDER.map { $0.lowercased() }

func normalizeLabel(_ value: String?) -> String {
    value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func classifyDeviceByLabel(_ labels: [String]) -> String? {
    let lowered = labels.map { $0.lowercased() }
    for (key, category) in LABEL_MAP {
        if lowered.contains(key) {
            return category.rawValue
        }
    }
    return nil
}

func getPrimaryLabel(for device: UIDevice) -> String {
    let override = normalizeLabel(device.label)
    if !override.isEmpty { return override }
    if let labels = device.labels, let first = labels.first {
        let normalized = normalizeLabel(first)
        if !normalized.isEmpty { return normalized }
    }
    return normalizeLabel(device.labelCategory) ?? OTHER_LABEL
}

func getGroupLabel(for device: UIDevice) -> String {
    let label = getPrimaryLabel(for: device)
    let idx = labelOrderLower.firstIndex(of: label.lowercased())
    return idx != nil ? LABEL_ORDER[idx!] : OTHER_LABEL
}

func sortLabels(_ labels: [String]) -> [String] {
    labels.sorted { a, b in
        let idxA = labelOrderLower.firstIndex(of: a.lowercased()) ?? LABEL_ORDER.count
        let idxB = labelOrderLower.firstIndex(of: b.lowercased()) ?? LABEL_ORDER.count
        if idxA != idxB { return idxA < idxB }
        return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }
}
