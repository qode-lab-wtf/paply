import Accelerate
import CoreML
import Foundation

/// CAM++ mit 800 Frames. Kürzere Ausschnitte werden vor der Merkmalsbildung zyklisch verlängert.
public final class CAMVoiceEmbedding {
    public static let modelID = "campplus-zh-en-advanced-coreml-fp16-800-v1"
    private let model: MLModel
    public init() throws {
        let config = MLModelConfiguration()
        // Kleines Profilmodell: CPU vermeidet zusätzliche ANE-Kompilierung und Speicherbelegung.
        config.computeUnits = .cpuOnly
        if let compiled = Bundle.module.url(forResource: "CAMPlus", withExtension: "mlmodelc") {
            // Xcode kompiliert auch die SwiftPM-Ressource beim App-Build.
            model = try MLModel(contentsOf: compiled, configuration: config)
        } else if let source = Bundle.module.url(forResource: "CAMPlus", withExtension: "mlpackage") {
            let compiled = try MLModel.compileModel(at: source)
            defer { try? FileManager.default.removeItem(at: compiled) }
            model = try MLModel(contentsOf: compiled, configuration: config)
        } else { throw ThoughtStoreError.unavailable }
    }

    public func embedding(samples: [Float]) throws -> [Float] {
        guard samples.count >= 16_000 else { throw ThoughtStoreError.unavailable }
        let features = try Self.features(samples: samples)
        let input = try MLMultiArray(shape: [1, 800, 80], dataType: .float32)
        for i in features.indices { input[i] = NSNumber(value: features[i]) }
        let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["features": MLFeatureValue(multiArray: input)]))
        guard let vector = result.featureValue(for: "var_7371")?.multiArrayValue else { throw ThoughtStoreError.unavailable }
        let values = (0..<vector.count).map { vector[$0].floatValue }
        let norm = sqrt(values.reduce(0) { $0 + $1 * $1 })
        guard norm.isFinite, norm > 0 else { throw ThoughtStoreError.unavailable }
        return values.map { $0 / norm }
    }
    /// Kaldi: 25 ms/10 ms, kein Dither, DC-Abzug, Präemphase 0,97, Povey, 80 Mel-Bänder, Mittelwertabzug.
    public static func features(samples: [Float]) throws -> [Float] {
        guard !samples.isEmpty,
              let fft = vDSP_DFT_zop_CreateSetup(nil, 512, .FORWARD) else { throw ThoughtStoreError.unavailable }
        defer { vDSP_DFT_DestroySetup(fft) }
        let window = (0..<400).map { Float(pow(0.5 - 0.5 * cos(2 * .pi * Double($0) / 399), 0.85)) }
        func mel(_ hz: Double) -> Double { 1127 * log(1 + hz / 700) }
        let low = mel(20), high = mel(7600), step = (high - low) / 81
        let weights = (0..<80).map { band in
            (0..<257).map { bin -> Float in
                let position = (mel(Double(bin) * 16000 / 512) - low) / step
                return Float(max(0, 1 - abs(position - Double(band + 1))))
            }
        }
        let zero = Array(repeating: Float(0), count: 512)
        var real = zero, imaginary = zero
        var features = Array(repeating: Float(0), count: 800 * 80)
        for frame in 0..<800 {
            var input = zero
            for i in 0..<400 {
                var index = frame * 160 - 120 + i
                if index < 0 { index = -index - 1 }
                if index >= 128000 { index = 255999 - index }
                input[i] = samples[index % samples.count]
            }
            let mean = input.prefix(400).reduce(0, +) / 400
            for i in 0..<400 { input[i] -= mean }
            for i in stride(from: 399, through: 1, by: -1) { input[i] -= 0.97 * input[i - 1] }
            input[0] *= 0.03
            for i in 0..<400 { input[i] *= window[i] }
            vDSP_DFT_Execute(fft, input, zero, &real, &imaginary)
            let power = (0..<257).map { real[$0] * real[$0] + imaginary[$0] * imaginary[$0] }
            for band in 0..<80 {
                let energy = zip(power, weights[band]).reduce(Float(0)) { $0 + $1.0 * $1.1 }
                features[frame * 80 + band] = log(max(Float.ulpOfOne, energy))
            }
        }
        for band in 0..<80 {
            let mean = (0..<800).reduce(Float(0)) { $0 + features[$1 * 80 + band] } / 800
            for frame in 0..<800 { features[frame * 80 + band] -= mean }
        }
        return features
    }
}
