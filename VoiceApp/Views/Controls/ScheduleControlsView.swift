import SwiftUI

struct ScheduleControlsView: View {
    @Bindable var calendar: CalendarProvider
    let pipelineActive: Bool
    let isSpeaking: Bool
    let onBriefMe: (String, String) -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if !calendar.isAuthorized {
                Button {
                    Task { await calendar.requestAccess() }
                } label: {
                    Label("Grant Calendar Access", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if calendar.todayEvents.isEmpty && calendar.reminders.isEmpty {
                            Text("Nothing on your schedule today")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        } else {
                            if !calendar.todayEvents.isEmpty {
                                Text("Today's Events")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(calendar.todayEvents, id: \.self) { event in
                                    Text(event)
                                        .font(.subheadline)
                                }
                            }

                            if !calendar.reminders.isEmpty {
                                Text("Reminders")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                ForEach(calendar.reminders, id: \.self) { reminder in
                                    Text(reminder)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)

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
                        let system = PromptBuilder.scheduleSystemPrompt()
                        let user = PromptBuilder.scheduleUserPrompt(
                            events: calendar.todayEvents,
                            reminders: calendar.reminders
                        )
                        onBriefMe(user, system)
                    } label: {
                        Label(
                            pipelineActive ? "Generating..." : "Brief Me",
                            systemImage: pipelineActive ? "ellipsis" : "calendar"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(pipelineActive)
                }
            }

            if let error = calendar.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
