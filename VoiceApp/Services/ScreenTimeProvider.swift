import FamilyControls
import Foundation

@MainActor
@Observable
final class ScreenTimeProvider {
    var isAuthorized = false
    var usageSummary: [String] = []
    var error: String?

    private let sharedDefaults = UserDefaults(suiteName: ScreenTimeConstants.appGroupID)

    private static let placeholderData = [
        "Instagram for 2 hours 15 minutes",
        "TikTok for 1 hour 45 minutes",
        "Safari for 1 hour 10 minutes",
        "Messages for 45 minutes",
        "YouTube for 35 minutes",
        "Total screen time 7 hours 20 minutes",
        "85 phone pickups",
    ]

    init() {
        let status = AuthorizationCenter.shared.authorizationStatus
        isAuthorized = status == .approved
        fetchUsageData()
    }

    func requestAccess() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
            fetchUsageData()
        } catch {
            self.error = "Screen Time access denied. Using placeholder data."
            fetchUsageData()
        }
    }

    /// Re-read shared UserDefaults after the extension has rendered.
    func refreshFromAppGroup() {
        fetchUsageData()
    }

    private func fetchUsageData() {
        if let stored = sharedDefaults?.stringArray(forKey: ScreenTimeConstants.usageSummaryKey),
           !stored.isEmpty
        {
            print("[ScreenTime] Using real data from extension: \(stored.count) items")
            usageSummary = stored
        } else {
            print("[ScreenTime] No extension data, using placeholder")
            usageSummary = Self.placeholderData
        }
    }
}
