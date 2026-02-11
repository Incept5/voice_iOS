import Foundation

enum AppMode: String, CaseIterable, Identifiable {
    case schedule
    case screenTime
    case fun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: "Schedule"
        case .screenTime: "Screen Time"
        case .fun: "Fun"
        }
    }

    var icon: String {
        switch self {
        case .schedule: "calendar"
        case .screenTime: "hourglass"
        case .fun: "theatermasks"
        }
    }
}
