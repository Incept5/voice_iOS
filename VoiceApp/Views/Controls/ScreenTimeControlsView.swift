import DeviceActivity
import SwiftUI

struct ScreenTimeControlsView: View {
    @Bindable var screenTime: ScreenTimeProvider
    let pipelineLabel: String?
    let isSpeaking: Bool
    let onRoast: (String, String) -> Void
    let onStop: () -> Void

    private var todayFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let interval = DateInterval(start: startOfDay, end: now)
        return DeviceActivityFilter(
            segment: .daily(during: interval)
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            if !screenTime.isAuthorized {
                VStack(spacing: 8) {
                    Text("Screen Time access lets us roast your app usage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        Task { await screenTime.requestAccess() }
                    } label: {
                        Label("Grant Screen Time Access", systemImage: "hourglass.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            } else {
                DeviceActivityReport(
                    DeviceActivityReport.Context(rawValue: ScreenTimeConstants.reportContext),
                    filter: todayFilter
                )
                .frame(maxHeight: 160)
                .onAppear {
                    // Give the extension time to render and write data
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        screenTime.refreshFromAppGroup()
                    }
                }

                if isSpeaking {
                    Button {
                        onStop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.large)
                } else {
                    Button {
                        screenTime.refreshFromAppGroup()
                        let system = PromptBuilder.screenTimeSystemPrompt()
                        let user = PromptBuilder.screenTimeUserPrompt(
                            data: screenTime.usageSummary
                        )
                        onRoast(user, system)
                    } label: {
                        HStack(spacing: 8) {
                            if pipelineLabel != nil {
                                ProgressView()
                                    .controlSize(.small)
                                Text(pipelineLabel ?? "")
                            } else {
                                Label("Roast My Screen Time", systemImage: "flame")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(pipelineLabel != nil)
                }
            }

            if let error = screenTime.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
