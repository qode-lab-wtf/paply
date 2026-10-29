import Foundation

/// Unveränderliche Artefakte der Pilotmessung; jede Datei wird vor Nutzung geprüft.
enum ConversationModelManifest {
    struct File: Sendable {
        let remote: String
        let local: String
        let bytes: Int64
        let sha256: String
    }
    static let revision = "25a90f97f254428d4b30374b76af9c74fdee8327"
    static let files: [File] = [
        .init(remote: "learnable_sil_emb.bin", local: "learnable_sil_emb.bin", bytes: 2048, sha256: "d4417b3c0eabdf7c47032fac2b5b5a7ee83d819a6ddda8fd8eaf74e2b5cc4ac7"),
        .init(remote: "monolithic/v2/Nemotron3Diarizer_fast128.mlmodelc/model.mil", local: "Nemotron3Diarizer_fast128.mlmodelc/model.mil", bytes: 502794, sha256: "e7c029a46d9f327bec4c47fc34e5d32ee2cec9ce596950af0c403d05146b4ead"),
        .init(remote: "monolithic/v2/Nemotron3Diarizer_fast128.mlmodelc/coremldata.bin", local: "Nemotron3Diarizer_fast128.mlmodelc/coremldata.bin", bytes: 758, sha256: "ebcca7245d8d774305752b9f2b79433ad1858f8a06df3b326e0ae6305d981d25"),
        .init(remote: "monolithic/v2/Nemotron3Diarizer_fast128.mlmodelc/weights/weight.bin", local: "Nemotron3Diarizer_fast128.mlmodelc/weights/weight.bin", bytes: 198590592, sha256: "e8c90d2d0e16787a420de6805fd5b7a95c116fac0163208b5bc4d8a9ae459ca4"),
        .init(remote: "monolithic/v2/Nemotron3Diarizer_fast128.mlmodelc/analytics/coremldata.bin", local: "Nemotron3Diarizer_fast128.mlmodelc/analytics/coremldata.bin", bytes: 243, sha256: "a71e06616a3ae7bddef06ce5dfc7fe523a286e489f63a8da2fc4f1e940d560a4")
    ]
}
