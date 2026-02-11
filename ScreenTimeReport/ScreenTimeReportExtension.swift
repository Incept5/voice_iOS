import DeviceActivity
import SwiftUI

// Constants duplicated here — extensions cannot import main app sources
private enum Constants {
    static let appGroupID = "group.com.incept5.VoiceApp"
    static let usageSummaryKey = "screenTimeUsageSummary"
    static let lastUpdatedKey = "screenTimeLastUpdated"
}

@main
struct ScreenTimeReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TotalActivityReport { usageLines in
            TotalActivityView(usageLines: usageLines)
        }
    }
}

// MARK: - Report Scene

struct TotalActivityReport: @preconcurrency DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "screenTimeRoast")
    let content: ([String]) -> TotalActivityView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> [String] {
        var appUsages: [(name: String, seconds: Int)] = []
        var totalSeconds = 0

        for await activityData in data {
            for await segment in activityData.activitySegments {
                for await category in segment.categories {
                    for await app in category.applications {
                        let name = app.application.localizedDisplayName
                            ?? app.application.bundleIdentifier
                            ?? "Unknown"
                        let seconds = Int(app.totalActivityDuration)
                        if seconds > 0 {
                            appUsages.append((name: name, seconds: seconds))
                            totalSeconds += seconds
                        }
                    }
                }
            }
        }

        appUsages.sort { $0.seconds > $1.seconds }
        let top = appUsages.prefix(7)

        var lines = top.map { formatDuration(name: $0.name, seconds: $0.seconds) }
        if totalSeconds > 0 {
            lines.append(formatDuration(name: "Total screen time", seconds: totalSeconds))
        }

        saveToAppGroup(lines)
        return lines
    }

    private func formatDuration(name: String, seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 && minutes > 0 {
            return "\(name) for \(hours) hours \(minutes) minutes"
        } else if hours > 0 {
            return "\(name) for \(hours) hours"
        } else {
            return "\(name) for \(minutes) minutes"
        }
    }

    private func saveToAppGroup(_ usage: [String]) {
        guard let defaults = UserDefaults(suiteName: Constants.appGroupID) else { return }
        defaults.set(usage, forKey: Constants.usageSummaryKey)
        defaults.set(Date().timeIntervalSince1970, forKey: Constants.lastUpdatedKey)
    }
}

// MARK: - View (kept minimal for 5MB RAM limit)

struct TotalActivityView: View {
    let usageLines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(usageLines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
