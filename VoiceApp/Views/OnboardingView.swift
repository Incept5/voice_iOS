import SwiftUI

struct OnboardingView: View {
    @Binding var hasSeenOnboarding: Bool
    @State private var currentPage = 0

    private let slides: [(icon: String, title: String, description: String)] = [
        ("brain.head.profile", "On-Device AI",
         "An MLX demo app. Text generation and voice cloning run entirely on your iPhone — no cloud, no data leaves your device."),
        ("calendar", "Schedule Briefing",
         "Get a spoken summary of your calendar events and reminders for the day."),
        ("hourglass", "Screen Time Roast",
         "Hear the AI roast your app usage habits. Real Screen Time integration is built in but requires Apple approval, so demo mode uses simulated data."),
        ("theatermasks", "Fun Mode",
         "Pick a personality, enter a topic, and hear AI-generated comedy spoken aloud."),
        ("mic.circle", "Voice Clone",
         "Record a short voice sample and clone it. The AI speaks in your voice.")
    ]

    var body: some View {
        ZStack {
            // Sphere background for visual identity
            SphereView(isActive: false, audioLevel: 0)
                .opacity(0.5)
                .ignoresSafeArea()

            TabView(selection: $currentPage) {
                ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                    VStack(spacing: 24) {
                        Spacer()

                        Image(systemName: slide.icon)
                            .font(.system(size: 64))
                            .foregroundStyle(.white)

                        Text(slide.title)
                            .font(.title.bold())
                            .foregroundStyle(.white)

                        Text(slide.description)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Spacer()

                        Button {
                            if index == slides.count - 1 {
                                hasSeenOnboarding = true
                            } else {
                                withAnimation {
                                    currentPage = index + 1
                                }
                            }
                        } label: {
                            Text(index == slides.count - 1 ? "Get Started" : "Continue")
                                .font(.headline)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.white, in: .capsule)
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 60)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .overlay(alignment: .topTrailing) {
                if currentPage < slides.count - 1 {
                    Button {
                        hasSeenOnboarding = true
                    } label: {
                        Text("Skip")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.trailing, 24)
                    .padding(.top, 16)
                }
            }
        }
        .background(.black)
    }
}
