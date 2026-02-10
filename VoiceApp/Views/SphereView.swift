import SwiftUI

/// Audio-reactive particle sphere with Fibonacci distribution
/// Adapted from previbe NativeSphereVisualizerView for iOS
struct SphereView: View {
    let isActive: Bool
    let audioLevel: Float
    var primaryColorHex: String = "#7C3AED"

    @State private var sphere = LivingSphere()

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            if size > 1 {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    Canvas { context, canvasSize in
                        guard canvasSize.width > 0, canvasSize.height > 0 else { return }

                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

                        sphere.update(time: time, isActive: isActive, audioLevel: audioLevel)

                        let baseRadius = size * 0.18
                        let speakingRadius = baseRadius * (1.0 + sphere.audioIntensity * 0.15)
                        let idleRadius = baseRadius * (0.75 + sphere.breathingPhase * 0.25)
                        let sphereRadius = speakingRadius * (1 - sphere.transitionProgress) + idleRadius * sphere.transitionProgress

                        let baseColor = Color(hex: primaryColorHex)

                        drawBloom(context: &context, center: center, radius: sphereRadius, color: baseColor)
                        drawParticles(context: &context, center: center, radius: sphereRadius, baseColor: baseColor)
                    }
                }
            }
        }
    }

    private func drawBloom(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        let speakingBloomRadius = radius * (1.3 + sphere.audioIntensity * 0.5)
        let idleBloomRadius = radius * (1.2 + sphere.breathingPhase * 0.15)
        let bloomRadius = speakingBloomRadius * (1 - sphere.transitionProgress) + idleBloomRadius * sphere.transitionProgress

        let speakingOpacity = 0.06 + sphere.audioIntensity * 0.15
        let idleOpacity = 0.03 + sphere.breathingPhase * 0.03
        let baseOpacity = speakingOpacity * (1 - sphere.transitionProgress) + idleOpacity * sphere.transitionProgress

        let gradient = Gradient(stops: [
            .init(color: color.opacity(baseOpacity), location: 0),
            .init(color: color.opacity(baseOpacity * 0.4), location: 0.4),
            .init(color: color.opacity(baseOpacity * 0.1), location: 0.7),
            .init(color: Color.clear, location: 1.0)
        ])
        let rect = CGRect(x: center.x - bloomRadius, y: center.y - bloomRadius,
                          width: bloomRadius * 2, height: bloomRadius * 2)
        context.fill(Circle().path(in: rect),
                     with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: bloomRadius))
    }

    private func drawParticles(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, baseColor: Color) {
        let sorted = sphere.particles.sorted { $0.z < $1.z }

        let speakingBrightness = 1.0 + sphere.audioIntensity * 0.6
        let idleBrightness = 0.4 + sphere.breathingPhase * 0.3
        let brightnessBoost = speakingBrightness * (1 - sphere.transitionProgress) + idleBrightness * sphere.transitionProgress

        for particle in sorted {
            let perspective = 1.0 / (1.0 - particle.z * 0.3)
            let screenX = center.x + particle.x * radius * perspective
            let screenY = center.y + particle.y * radius * perspective

            let depthFactor = (particle.z + 1.0) / 2.0
            let size = particle.size * (0.4 + depthFactor * 0.6) * perspective
            let alpha = (0.4 + depthFactor * 0.6) * particle.brightness * brightnessBoost

            guard size > 0.3 && alpha > 0.05 else { continue }

            let color: Color
            switch particle.colorType {
            case .primary: color = baseColor
            case .cyan: color = Color(red: 0.4, green: 0.75, blue: 1.0)
            case .blue: color = Color(red: 0.35, green: 0.55, blue: 0.95)
            case .magenta: color = Color(red: 0.85, green: 0.4, blue: 0.75)
            case .white: color = Color.white
            }

            let rect = CGRect(x: screenX - size / 2, y: screenY - size / 2, width: size, height: size)
            context.fill(Circle().path(in: rect), with: .color(color.opacity(min(alpha, 1.0))))
        }
    }
}

// MARK: - Living Sphere Model (class to avoid @State mutation during render)

@MainActor
final class LivingSphere {
    enum ColorType { case primary, cyan, blue, magenta, white }

    struct Particle {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var z: CGFloat = 0
        var theta: CGFloat = 0
        var phi: CGFloat = 0
        var baseRadius: CGFloat = 1.0
        var size: CGFloat = 2.0
        var baseBrightness: CGFloat = 1.0
        var brightness: CGFloat = 1.0
        var colorType: ColorType = .primary
    }

    var particles: [Particle] = []
    var audioIntensity: CGFloat = 0
    var breathingPhase: CGFloat = 0.5
    var transitionProgress: CGFloat = 0

    private var rotation: CGFloat = 0
    private var wavePhase: CGFloat = 0
    private var breathingTime: CGFloat = 0
    private var smoothedAudio: CGFloat = 0
    private var lastTime: Double = 0

    init() {
        createParticles()
        initializePositions()
    }

    private func createParticles() {
        let count = 3000
        let goldenRatio = (1.0 + sqrt(5.0)) / 2.0

        particles = (0..<count).map { i in
            var p = Particle()

            p.theta = CGFloat(2.0 * .pi * Double(i) / goldenRatio)
            p.phi = CGFloat(acos(1.0 - 2.0 * (Double(i) + 0.5) / Double(count)))

            let radiusRand = CGFloat.random(in: 0...1)
            if radiusRand < 0.65 {
                p.baseRadius = CGFloat.random(in: 0.75...1.0)
            } else if radiusRand < 0.88 {
                p.baseRadius = CGFloat.random(in: 1.0...1.2)
            } else {
                p.baseRadius = CGFloat.random(in: 1.2...1.5)
            }

            let r = CGFloat.random(in: 0...1)
            if r < 0.7 {
                p.size = CGFloat.random(in: 0.5...1.0)
            } else if r < 0.9 {
                p.size = CGFloat.random(in: 1.0...1.8)
            } else {
                p.size = CGFloat.random(in: 1.8...2.8)
            }

            let c = CGFloat.random(in: 0...1)
            if c < 0.35 {
                p.colorType = .blue
            } else if c < 0.60 {
                p.colorType = .cyan
            } else if c < 0.78 {
                p.colorType = .primary
            } else if c < 0.92 {
                p.colorType = .magenta
            } else {
                p.colorType = .white
            }

            p.baseBrightness = CGFloat.random(in: 0.5...1.0)
            p.brightness = p.baseBrightness
            return p
        }
    }

    private func initializePositions() {
        for i in particles.indices {
            var p = particles[i]
            let sinPhi = sin(p.phi)
            let cosPhi = cos(p.phi)
            let sinTheta = sin(p.theta)
            let cosTheta = cos(p.theta)
            p.x = sinPhi * cosTheta * p.baseRadius
            p.y = cosPhi * p.baseRadius
            p.z = sinPhi * sinTheta * p.baseRadius
            particles[i] = p
        }
    }

    func update(time: Double, isActive: Bool, audioLevel: Float) {
        let deltaTime: CGFloat
        if lastTime == 0 {
            deltaTime = 1.0 / 60.0
        } else {
            deltaTime = min(CGFloat(time - lastTime), 0.1)
        }
        lastTime = time

        let targetAudio = isActive ? CGFloat(audioLevel) : 0
        smoothedAudio += (targetAudio - smoothedAudio) * 0.5
        audioIntensity = smoothedAudio

        let targetTransition: CGFloat = (audioIntensity > 0.05) ? 0 : 1
        if targetTransition > transitionProgress {
            transitionProgress += deltaTime * 1.25
        } else {
            transitionProgress += (targetTransition - transitionProgress) * 0.3
        }
        transitionProgress = max(0, min(1, transitionProgress))

        breathingTime += deltaTime * 0.8
        breathingPhase = CGFloat(0.5 + 0.5 * sin(Double(breathingTime)))

        let rotationSpeed: CGFloat = 0.3 + smoothedAudio * 2.5
        rotation += rotationSpeed * deltaTime

        let waveSpeed: CGFloat = 2.0 + smoothedAudio * 8.0
        wavePhase += waveSpeed * deltaTime

        let waveAmount: CGFloat = 0.05 + smoothedAudio * 0.7

        for i in particles.indices {
            var p = particles[i]

            let rotatedTheta = p.theta + rotation
            let sinPhi = sin(p.phi)
            let cosPhi = cos(p.phi)
            let sinTheta = sin(rotatedTheta)
            let cosTheta = cos(rotatedTheta)

            let wave1 = sin(Double(p.phi * 2 + wavePhase)) * cos(Double(rotatedTheta * 2 - wavePhase * 0.7))
            let wave2 = sin(Double(p.phi * 3 - wavePhase * 0.5))
            let waveDisplacement = CGFloat(wave1 * 0.6 + wave2 * 0.4) * waveAmount

            let radius = p.baseRadius * (1.0 + waveDisplacement)

            p.x = sinPhi * cosTheta * radius
            p.y = cosPhi * radius
            p.z = sinPhi * sinTheta * radius
            p.brightness = p.baseBrightness * (0.85 + waveDisplacement * 2)

            particles[i] = p
        }
    }
}

#Preview("Speaking") {
    ZStack {
        Color.black
        SphereView(isActive: true, audioLevel: 0.5)
    }
}

#Preview("Idle") {
    ZStack {
        Color.black
        SphereView(isActive: false, audioLevel: 0)
    }
}
