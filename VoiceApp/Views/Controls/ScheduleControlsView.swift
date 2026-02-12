import SwiftUI

struct ScheduleControlsView: View {
    @Bindable var calendar: CalendarProvider
    let pipelineLabel: String?
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
                            VStack(spacing: 8) {
                                Image(systemName: "calendar.badge.checkmark")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("Nothing on your schedule today")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            if !calendar.todayEvents.isEmpty {
                                Text("Today's Events")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(calendar.todayEvents, id: \.self) { event in
                                    Label(event, systemImage: "calendar")
                                        .font(.subheadline)
                                }
                            }

                            if !calendar.reminders.isEmpty {
                                Text("Reminders")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                ForEach(calendar.reminders, id: \.self) { reminder in
                                    Label(reminder, systemImage: "checklist")
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)

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
                        HStack(spacing: 8) {
                            if pipelineLabel != nil {
                                ProgressView()
                                    .controlSize(.small)
                                Text(pipelineLabel ?? "")
                            } else {
                                Label("Brief Me", systemImage: "calendar")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(pipelineLabel != nil)
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
