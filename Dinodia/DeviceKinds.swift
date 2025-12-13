import Foundation

private let primaryCategories: Set<String> = [
    "light",
    "blind",
    "tv",
    "speaker",
    "boiler",
    "spotify",
    "switch",
    "thermostat",
    "media",
    "vacuum",
    "camera",
    "security",
]

private let sensorCategories: Set<String> = ["sensor", "motion sensor"]

private func normalizeCategory(_ value: String?) -> String {
    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

func isDetailDevice(state: String) -> Bool {
    let trimmed = state.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return false }
    if trimmed.lowercased() == "unavailable" { return true }
    return Double(trimmed) != nil
}

func isSensorDevice(_ device: UIDevice) -> Bool {
    let category = normalizeCategory(device.labelCategory)
    if sensorCategories.contains(category) { return true }
    if isDetailDevice(state: device.state) { return true }
    return false
}

func isPrimaryDevice(_ device: UIDevice) -> Bool {
    let category = normalizeCategory(device.labelCategory)
    if primaryCategories.contains(category) { return true }
    if isSensorDevice(device) { return false }
    return !isDetailDevice(state: device.state)
}
