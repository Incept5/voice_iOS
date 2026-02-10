// Copyright © Anthony DePasquale
//
// Chatterbox Turbo TTS Benchmark - Swift MLX Implementation
// ==========================================================
// Benchmarks the Swift mlx-swift-audio implementation of Chatterbox Turbo.
// Uses the same model, reference audio, and test texts as the Python benchmark
// for fair comparison.
//
// Run with: xcodebuild test-without-building -only-testing:MLXAudioTests/ChatterboxTurboBenchmark

import AVFoundation
import Foundation
import MLX
import MLXRandom
import Testing

@testable import MLXAudio

// MARK: - Benchmark Configuration

private let kWarmupIterations = 2
private let kBenchmarkIterations = 5
private let kOutputDir = URL(fileURLWithPath: "/tmp/chatterbox-turbo-benchmark")

// Test texts matching Python benchmark
private let kTestTexts = [
  // Short (< 50 chars)
  "Hello, this is a quick test of the system.",

  // Medium (50-150 chars)
  "The examination and testimony of the experts enabled the commission to conclude that five shots may have been fired.",

  // Long (150-300 chars)
  "Artificial intelligence has made remarkable progress in recent years. From natural language processing to computer vision, AI systems are now capable of performing tasks that were once thought to require human intelligence. This rapid advancement has significant implications for many industries.",

  // Very long (300+ chars)
  "The history of computing is a fascinating journey from mechanical calculators to modern quantum computers. In the early days, pioneers like Charles Babbage and Ada Lovelace laid the groundwork for what would become the digital revolution. Today, we carry more computing power in our pockets than existed in the entire world just a few decades ago. This remarkable progress continues to accelerate, driven by innovations in hardware, software, and artificial intelligence.",
]

// MARK: - Benchmark Result Types

struct BenchmarkIterationResult: Codable {
  let iteration: Int
  let generationTimeSeconds: Double
  let audioDurationSeconds: Double
  let totalSamples: Int
  let samplesPerSecond: Double
  let realTimeFactor: Double
}

struct BenchmarkTextResult: Codable {
  let text: String
  let textLength: Int
  var iterations: [BenchmarkIterationResult]
  var meanGenerationTime: Double?
  var stdGenerationTime: Double?
  var meanRtf: Double?
  var stdRtf: Double?
  var meanSamplesPerSecond: Double?
  var stdSamplesPerSecond: Double?
}

struct BenchmarkResults: Codable {
  let implementation: String
  let model: String
  let quantization: String
  let device: String
  let warmupIterations: Int
  let benchmarkIterations: Int
  var modelLoadTimeSeconds: Double?
  var conditioningTimeSeconds: Double?
  var texts: [BenchmarkTextResult]
  var overallMeanRtf: Double?
  var overallMeanSamplesPerSecond: Double?
}

// MARK: - Statistics Helpers

private func mean(_ values: [Double]) -> Double {
  guard !values.isEmpty else { return 0 }
  return values.reduce(0, +) / Double(values.count)
}

private func stdDev(_ values: [Double]) -> Double {
  guard values.count > 1 else { return 0 }
  let avg = mean(values)
  let sumOfSquaredAvgDiff = values.map { ($0 - avg) * ($0 - avg) }.reduce(0, +)
  return sqrt(sumOfSquaredAvgDiff / Double(values.count - 1))
}

// MARK: - Benchmark Test Suite

@Suite(.serialized)
struct ChatterboxTurboBenchmark {
  /// Reference audio from LJ Speech dataset (public domain)
  static let referenceAudioURL = URL(string: "https://keithito.com/LJ-Speech-Dataset/LJ037-0171.wav")!

  /// Sample rate for output audio
  static let sampleRate = 24000

  /// Download audio from URL
  static func downloadAudio(from url: URL) async throws -> (audio: MLXArray, sampleRate: Int) {
    let cacheURL = try await TestAudioCache.downloadToFile(from: url)
    return try loadAudioFile(at: cacheURL)
  }

  /// Load audio file
  static func loadAudioFile(at url: URL) throws -> (audio: MLXArray, sampleRate: Int) {
    let file = try AVAudioFile(forReading: url)

    guard let buffer = AVAudioPCMBuffer(
      pcmFormat: file.processingFormat,
      frameCapacity: AVAudioFrameCount(file.length)
    ) else {
      throw TestError(message: "Failed to create buffer")
    }

    try file.read(into: buffer)

    guard let floatData = buffer.floatChannelData else {
      throw TestError(message: "No float data in buffer")
    }

    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)

    var samples = [Float](repeating: 0, count: frameCount)
    if channelCount == 1 {
      for i in 0 ..< frameCount {
        samples[i] = floatData[0][i]
      }
    } else {
      for i in 0 ..< frameCount {
        var sum: Float = 0
        for ch in 0 ..< channelCount {
          sum += floatData[ch][i]
        }
        samples[i] = sum / Float(channelCount)
      }
    }

    return (audio: MLXArray(samples), sampleRate: Int(file.fileFormat.sampleRate))
  }

  // MARK: - Main Benchmark Test

  @Test @MainActor func benchmarkChatterboxTurbo() async throws {
    print("\n" + String(repeating: "=", count: 60))
    print("CHATTERBOX TURBO BENCHMARK - Swift MLX Implementation")
    print(String(repeating: "=", count: 60))

    var results = BenchmarkResults(
      implementation: "Swift MLX (mlx-swift-audio)",
      model: "mlx-community/chatterbox-turbo-4bit",
      quantization: "q4",
      device: "Apple Silicon (Metal)",
      warmupIterations: kWarmupIterations,
      benchmarkIterations: kBenchmarkIterations,
      texts: []
    )

    // Configure memory limits
    MLXMemory.configure(cacheLimit: 512 * 1024 * 1024)

    // Step 1: Load model
    print("\nLoading Chatterbox Turbo model...")
    let modelLoadStart = CFAbsoluteTimeGetCurrent()
    let model = try await ChatterboxTurboTestHelper.getOrLoadModel()
    let modelLoadTime = CFAbsoluteTimeGetCurrent() - modelLoadStart
    results.modelLoadTimeSeconds = modelLoadTime
    print("Model loaded in \(String(format: "%.2f", modelLoadTime))s")

    // Step 2: Prepare reference audio conditioning
    print("\nPreparing reference audio conditioning...")
    let condStart = CFAbsoluteTimeGetCurrent()
    let (refAudio, refSampleRate) = try await Self.downloadAudio(from: Self.referenceAudioURL)
    let conditionals = model.prepareConditionals(refWav: refAudio, refSr: refSampleRate)
    eval(conditionals.t3.speakerEmb)
    eval(conditionals.gen.embedding)
    let condTime = CFAbsoluteTimeGetCurrent() - condStart
    results.conditioningTimeSeconds = condTime
    print("Conditioning prepared in \(String(format: "%.2f", condTime))s")

    // Create output directory
    try FileManager.default.createDirectory(at: kOutputDir, withIntermediateDirectories: true)

    // Step 3: Warmup runs
    print("\n" + String(repeating: "=", count: 60))
    print("Running \(kWarmupIterations) warmup iteration(s)...")
    print(String(repeating: "=", count: 60))

    let warmupText = kTestTexts[0]
    for i in 0 ..< kWarmupIterations {
      print("Warmup \(i + 1)/\(kWarmupIterations)...")
      let audio = model.generate(text: warmupText, conds: conditionals)
      eval(audio)
      MLXMemory.clearCache()
    }

    // Step 4: Benchmark each text
    print("\n" + String(repeating: "=", count: 60))
    print("Running \(kBenchmarkIterations) benchmark iteration(s) per text...")
    print(String(repeating: "=", count: 60))

    for (textIdx, text) in kTestTexts.enumerated() {
      var textResult = BenchmarkTextResult(
        text: text,
        textLength: text.count,
        iterations: []
      )

      let textPreview = text.count > 60 ? String(text.prefix(60)) + "..." : text
      print("\nText \(textIdx + 1)/\(kTestTexts.count) (\(text.count) chars):")
      print("  '\(textPreview)'")

      for iteration in 0 ..< kBenchmarkIterations {
        MLXMemory.clearCache()

        // Measure generation
        let genStart = CFAbsoluteTimeGetCurrent()
        let audio = model.generate(text: text, conds: conditionals)
        eval(audio)
        let genTime = CFAbsoluteTimeGetCurrent() - genStart

        // Extract samples
        let samples = audio.asArray(Float.self)
        let totalSamples = samples.count
        let audioDuration = Double(totalSamples) / Double(Self.sampleRate)
        let rtf = audioDuration > 0 ? genTime / audioDuration : 0
        let samplesPerSec = genTime > 0 ? Double(totalSamples) / genTime : 0

        let iterResult = BenchmarkIterationResult(
          iteration: iteration + 1,
          generationTimeSeconds: genTime,
          audioDurationSeconds: audioDuration,
          totalSamples: totalSamples,
          samplesPerSecond: samplesPerSec,
          realTimeFactor: rtf
        )
        textResult.iterations.append(iterResult)

        print("  Iteration \(iteration + 1): \(String(format: "%.3f", genTime))s, RTF: \(String(format: "%.3f", rtf))x, \(Int(samplesPerSec)) samples/s")
      }

      // Calculate aggregates
      let genTimes = textResult.iterations.map { $0.generationTimeSeconds }
      let rtfs = textResult.iterations.map { $0.realTimeFactor }
      let samplesRates = textResult.iterations.map { $0.samplesPerSecond }

      textResult.meanGenerationTime = mean(genTimes)
      textResult.stdGenerationTime = stdDev(genTimes)
      textResult.meanRtf = mean(rtfs)
      textResult.stdRtf = stdDev(rtfs)
      textResult.meanSamplesPerSecond = mean(samplesRates)
      textResult.stdSamplesPerSecond = stdDev(samplesRates)

      print(
        "  Average: \(String(format: "%.3f", textResult.meanGenerationTime!))s "
          + "(±\(String(format: "%.3f", textResult.stdGenerationTime!))s), "
          + "RTF: \(String(format: "%.3f", textResult.meanRtf!))x"
      )

      results.texts.append(textResult)
    }

    // Overall summary
    let allMeanRtfs = results.texts.compactMap { $0.meanRtf }
    let allMeanSamples = results.texts.compactMap { $0.meanSamplesPerSecond }

    results.overallMeanRtf = mean(allMeanRtfs)
    results.overallMeanSamplesPerSecond = mean(allMeanSamples)

    print("\n" + String(repeating: "=", count: 60))
    print("BENCHMARK SUMMARY")
    print(String(repeating: "=", count: 60))
    print("Implementation:         Swift MLX (mlx-swift-audio)")
    print("Model:                  mlx-community/chatterbox-turbo-4bit")
    print("Quantization:           q4")
    print("Model load time:        \(String(format: "%.2f", modelLoadTime))s")
    print("Conditioning time:      \(String(format: "%.2f", condTime))s")
    print("Overall mean RTF:       \(String(format: "%.3f", results.overallMeanRtf!))x")
    print("Overall samples/sec:    \(Int(results.overallMeanSamplesPerSecond!))")
    print(String(repeating: "=", count: 60))

    // Save results to JSON
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.keyEncodingStrategy = .convertToSnakeCase

    if let data = try? encoder.encode(results) {
      let outputPath = kOutputDir.appendingPathComponent("benchmark_swift_results.json")
      try data.write(to: outputPath)
      print("\nResults saved to: \(outputPath.path)")

      // Also save to /tmp for comparison script
      try data.write(to: URL(fileURLWithPath: "/tmp/benchmark_swift_results.json"))
    }
  }
}
