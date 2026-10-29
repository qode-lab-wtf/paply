import Foundation
import FluidAudio
import CoreML
import AVFoundation
@main struct Bench {
 static func main() async throws {
  let args = CommandLine.arguments
  guard args.count >= 4 else { fatalError("FluidBench audio output.json models [speakers] [step]") }
  if args.count > 4 && args[4] == "nemotron" {
   let config = Nemotron3Config.preset(named: args.count > 5 ? args[5] : "c128-split-w8a8")!
   let start = Date()
   let route: MLComputeUnits = args.count > 6 && args[6] == "cpu" ? .cpuOnly : (args.count > 6 && args[6] == "ane" ? .cpuAndNeuralEngine : .all)
   let models = try await Nemotron3Models.loadFromHuggingFace(config: config, cacheDirectory: URL(fileURLWithPath: args[3]), computeUnits: route)
   let loaded = Date()
   let diarizer = Nemotron3Diarizer(config: config, models: models)
   var probs: [Float] = []
   var frames = 0
   if args.contains("--stream") {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[1]))
    guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 160000) else {
     fatalError("Streaming benchmark requires mono 16 kHz")
    }
    while file.framePosition < file.length {
     try file.read(into: buffer)
     guard let channel = buffer.floatChannelData?[0] else { fatalError("Expected float PCM") }
     diarizer.appendAudio(Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
     for chunk in try diarizer.processBufferedAudio() { probs.append(contentsOf: chunk.probabilities); frames += chunk.frameCount }
    }
    for chunk in try diarizer.finishStream() { probs.append(contentsOf: chunk.probabilities); frames += chunk.frameCount }
   } else {
    let samples = try AudioConverter().resampleAudioFile(path: args[1])
    (probs, frames) = try diarizer.processComplete(samples)
   }
   let segments = Nemotron3Diarizer.segments(probabilities: probs, frameCount: frames, minDurationSeconds: args.contains("--short-turns") ? 0.05 : 0.2)
   let output: [String: Any] = ["segments": segments.map { ["start": $0.startSeconds, "end": $0.endSeconds, "speaker": String($0.speakerIndex)] as [String: Any] }, "seconds": Date().timeIntervalSince(loaded), "load_seconds": loaded.timeIntervalSince(start)]
   try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: args[2]))
   return
  }
  var config = OfflineDiarizerConfig()
  if args.count > 4, let n = Int(args[4]), n > 0 { config.clustering.numSpeakers = n }
  if args.count > 5, let step = Double(args[5]) { config.segmentation.stepRatio = step }
  let manager = OfflineDiarizerManager(config: config)
  let start = Date()
  let ml = MLModelConfiguration(); ml.computeUnits = .all
  try await manager.prepareModels(directory: URL(fileURLWithPath: args[3]), configuration: ml)
  let loaded = Date()
  let result = try await manager.process(URL(fileURLWithPath: args[1]))
  let output: [String: Any] = ["segments": result.segments.map { ["start": $0.startTimeSeconds, "end": $0.endTimeSeconds, "speaker": $0.speakerId] as [String: Any] }, "seconds": Date().timeIntervalSince(loaded), "load_seconds": loaded.timeIntervalSince(start), "embeddings": result.speakerDatabase ?? [:]]
  try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[2]))
 }
}
