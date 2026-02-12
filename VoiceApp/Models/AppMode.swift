import Foundation

enum AppMode: String, CaseIterable, Identifiable {
    case schedule
    case screenTime
    case fun
    case voiceClone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: "Schedule"
        case .screenTime: "Screen Time"
        case .fun: "Fun"
        case .voiceClone: "Voice"
        }
    }

    var icon: String {
        switch self {
        case .schedule: "calendar"
        case .screenTime: "hourglass"
        case .fun: "theatermasks"
        case .voiceClone: "mic.circle"
        }
    }

    var filledIcon: String {
        switch self {
        case .schedule: "calendar.circle.fill"
        case .screenTime: "hourglass.circle.fill"
        case .fun: "theatermasks.fill"
        case .voiceClone: "mic.circle.fill"
        }
    }
}
