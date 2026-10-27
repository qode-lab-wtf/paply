import Foundation

/// Abgeleiteter Index je Gedanke (KONZEPT §6.3): Schlagwort-Häufigkeiten (BM25) und Embedding.
/// Liegt als `embeddings.bin` neben den Gedanken, ist jederzeit neu berechenbar und wird bei
/// jedem Lesefehler verworfen.
public struct LocalIndex: Sendable {
    public struct Entry: Sendable, Equatable {
        public var id: String
        /// stabiler Hash von Titel + Text + Sprache: ändert er sich, wird neu berechnet
        public var contentHash: UInt64
        public var language: String?
        public var terms: [String: Int]
        public var length: Int
        public var vector: EmbeddingVector?

        public init(id: String, contentHash: UInt64, language: String?, terms: [String: Int], vector: EmbeddingVector?) {
            self.id = id
            self.contentHash = contentHash
            self.language = language
            self.terms = terms
            self.length = terms.values.reduce(0, +)
            self.vector = vector
        }
    }

    public private(set) var entries: [String: Entry] = [:]
    /// Dokumenthäufigkeit je Term
    public private(set) var documentFrequency: [String: Int] = [:]
    public private(set) var totalLength = 0

    public init() {}

    public var count: Int { entries.count }
    public var averageLength: Double { entries.isEmpty ? 1 : max(1, Double(totalLength) / Double(entries.count)) }

    public subscript(id: String) -> Entry? { entries[id] }

    public mutating func upsert(_ entry: Entry) {
        remove(entry.id)
        entries[entry.id] = entry
        totalLength += entry.length
        for term in entry.terms.keys { documentFrequency[term, default: 0] += 1 }
    }

    public mutating func remove(_ id: String) {
        guard let old = entries.removeValue(forKey: id) else { return }
        totalLength -= old.length
        for term in old.terms.keys {
            let next = (documentFrequency[term] ?? 1) - 1
            documentFrequency[term] = next > 0 ? next : nil
        }
    }

    /// BM25-IDF (immer ≥ 0)
    public func idf(_ term: String) -> Double {
        let n = Double(entries.count)
        let df = Double(documentFrequency[term] ?? 0)
        return log(1 + (n - df + 0.5) / (df + 0.5))
    }

    /// BM25 der Anfrage gegen ein Dokument (k1 = 1,2, b = 0,75).
    public func bm25(query: [String: Int], document: Entry, k1: Double = 1.2, b: Double = 0.75) -> Double {
        var score = 0.0
        let norm = k1 * (1 - b + b * Double(document.length) / averageLength)
        for term in query.keys {
            guard let tf = document.terms[term] else { continue }
            let f = Double(tf)
            score += idf(term) * f * (k1 + 1) / (f + norm)
        }
        return score
    }

    /// Höchstwert für die Normierung: die Anfrage gegen sich selbst als Dokument.
    public func selfScore(query: [String: Int], k1: Double = 1.2, b: Double = 0.75) -> Double {
        let length = query.values.reduce(0, +)
        let norm = k1 * (1 - b + b * Double(length) / averageLength)
        return query.reduce(0.0) { sum, item in
            let f = Double(item.value)
            return sum + idf(item.key) * f * (k1 + 1) / (f + norm)
        }
    }

    /// Mittelwert aller Vektoren eines Raums (gegen die Anisotropie gemittelter Token-Vektoren).
    public func meanVector(model: EmbeddingModel, space: String) -> [Float]? {
        var sum: [Float]?
        var count = 0
        for entry in entries.values {
            guard let vector = entry.vector, vector.model == model, vector.space == space else { continue }
            if sum == nil { sum = [Float](repeating: 0, count: vector.values.count) }
            guard sum!.count == vector.values.count else { continue }
            for i in 0..<vector.values.count { sum![i] += vector.values[i] }
            count += 1
        }
        guard let sum, count >= 2 else { return nil }
        return sum.map { $0 / Float(count) }
    }

    // MARK: Datei (`embeddings.bin`)

    private static let magic = Array("PLX1".utf8)
    private static let version: UInt32 = 1

    public func encoded() -> Data {
        var out = BinaryWriter()
        out.bytes(Self.magic)
        out.u32(Self.version)
        out.u32(UInt32(entries.count))
        for entry in entries.values.sorted(by: { $0.id < $1.id }) {
            out.string(entry.id)
            out.u64(entry.contentHash)
            out.string(entry.language ?? "")
            out.u32(UInt32(entry.terms.count))
            for (term, count) in entry.terms.sorted(by: { $0.key < $1.key }) {
                out.string(term)
                out.u32(UInt32(count))
            }
            if let vector = entry.vector {
                out.u8(vector.model == .contextual ? 2 : 1)
                out.string(vector.space)
                out.u32(UInt32(vector.values.count))
                vector.values.withUnsafeBytes { out.data.append(contentsOf: $0) }
            } else {
                out.u8(0)
            }
        }
        return out.data
    }

    public static func decode(_ data: Data) -> LocalIndex? {
        var input = BinaryReader(data: data)
        guard input.bytes(4) == magic, input.u32() == version, let count = input.u32() else { return nil }
        var index = LocalIndex()
        for _ in 0..<count {
            guard let id = input.string(), let hash = input.u64(), let language = input.string(),
                  let termCount = input.u32(), termCount < 100_000 else { return nil }
            var terms: [String: Int] = [:]
            for _ in 0..<termCount {
                guard let term = input.string(), let value = input.u32() else { return nil }
                terms[term] = Int(value)
            }
            guard let kind = input.u8() else { return nil }
            var vector: EmbeddingVector?
            if kind != 0 {
                guard let space = input.string(), let dim = input.u32(), dim < 10_000,
                      let raw = input.bytes(Int(dim) * 4) else { return nil }
                let values = raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                vector = EmbeddingVector(model: kind == 2 ? .contextual : .sentence, space: space, values: values)
            }
            index.upsert(Entry(id: id, contentHash: hash, language: language.isEmpty ? nil : language, terms: terms, vector: vector))
        }
        return index
    }
}

private struct BinaryWriter {
    var data = Data()
    mutating func bytes(_ value: [UInt8]) { data.append(contentsOf: value) }
    mutating func u8(_ value: UInt8) { data.append(value) }
    mutating func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    mutating func u64(_ value: UInt64) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    mutating func string(_ value: String) {
        let utf8 = Array(value.utf8)
        u32(UInt32(utf8.count))
        data.append(contentsOf: utf8)
    }
}

private struct BinaryReader {
    let data: Data
    var offset = 0

    init(data: Data) { self.data = Data(data) }

    mutating func bytes(_ count: Int) -> [UInt8]? {
        guard count >= 0, offset + count <= data.count else { return nil }
        defer { offset += count }
        return Array(data[(data.startIndex + offset)..<(data.startIndex + offset + count)])
    }

    mutating func u8() -> UInt8? { bytes(1)?.first }

    mutating func u32() -> UInt32? {
        guard let raw = bytes(4) else { return nil }
        return raw.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    }

    mutating func u64() -> UInt64? {
        guard let raw = bytes(8) else { return nil }
        return raw.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
    }

    mutating func string() -> String? {
        guard let length = u32(), length < 1_000_000, let raw = bytes(Int(length)) else { return nil }
        return String(bytes: raw, encoding: .utf8)
    }
}
