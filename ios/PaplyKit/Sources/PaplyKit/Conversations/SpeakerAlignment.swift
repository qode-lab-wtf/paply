import Foundation

public struct ConversationWord: Codable, Sendable, Equatable {
    public var word: String
    public var start: Double
    public var end: Double
    public init(word: String, start: Double, end: Double) { self.word = word; self.start = start; self.end = end }
}

public enum SpeakerAlignment {
    public struct Result: Sendable {
        public var speakers: [ConversationSpeaker]
        public var utterances: [ConversationUtterance]
        public var prints: [String: VoicePrint]
    }
    public static func align(words: [ConversationWord], diarization: Diarization, gaps: [ConversationGap] = []) -> Result {
        let clusters = diarization.centroids.keys.sorted()
        var parent = Dictionary(uniqueKeysWithValues: clusters.map { ($0, $0) })
        func root(_ c: Int) -> Int { var c = c; while let p = parent[c], p != c { c = p }; return c }
        for a in clusters { for b in clusters where b > a {
            let score = SpeakerThresholds.cosine(diarization.centroids[a]!, diarization.centroids[b]!)
            let small = min(diarization.speechSeconds[a] ?? 0, diarization.speechSeconds[b] ?? 0) < SpeakerThresholds.fragmentSeconds
            if score >= (small ? SpeakerThresholds.fragmentMerge : SpeakerThresholds.merge) { parent[root(b)] = root(a) }
        } }
        let segments = diarization.segments.filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
        var totals: [Int: Double] = [:]
        for s in segments { totals[root(s.cluster), default: 0] += s.end - s.start }
        let ordered = totals.keys.sorted { totals[$0] == totals[$1] ? $0 < $1 : totals[$0]! > totals[$1]! }
        let ids = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1, "S\($0 + 1)") })
        let speakers = ordered.enumerated().map { ConversationSpeaker(id: ids[$1]!, speechSeconds: totals[$1]!, colorIndex: $0 + 1) }
        var prints: [String: VoicePrint] = [:]
        for c in ordered { if let vector = diarization.centroids[c] {
            prints[ids[c]!] = VoicePrint(vector: vector, model: diarization.model, seconds: totals[c]!, source: .conversation)
        } }
        struct Assigned { var word: ConversationWord; var cluster: Int; var uncertain: Bool; var strength: Double }
        var assigned: [Assigned] = []
        for word in words.sorted(by: { $0.start < $1.start }) where word.start.isFinite && word.end.isFinite && word.end >= word.start {
            var overlap: [Int: Double] = [:]
            for s in segments { overlap[root(s.cluster), default: 0] += max(0, min(s.end, word.end) - max(s.start, word.start)) }
            let ranked = overlap.keys.sorted { overlap[$0] == overlap[$1] ? $0 < $1 : overlap[$0]! > overlap[$1]! }
            guard var winner = ranked.first else { continue }
            let best = overlap[winner] ?? 0
            if best == 0, let nearest = segments.min(by: { min(abs($0.start - word.start), abs($0.end - word.end)) < min(abs($1.start - word.start), abs($1.end - word.end)) }) { winner = root(nearest.cluster) }
            let second = ranked.dropFirst().first.map { overlap[$0] ?? 0 } ?? 0
            assigned.append(Assigned(word: word, cluster: winner, uncertain: best == 0 || second > best * 0.25, strength: best - second))
        }
        // Nur schwache Wechsel glätten; klare Wechsel mitten im Satz bleiben erhalten.
        var start = 0
        for i in assigned.indices {
            let boundary = i == assigned.count - 1 || assigned[i].word.word.last.map { ".!?".contains($0) } == true || assigned[i + 1].word.start - assigned[i].word.end > 0.7
            guard boundary else { continue }
            var votes: [Int: Double] = [:]
            for j in start...i { votes[assigned[j].cluster, default: 0] += assigned[j].word.end - assigned[j].word.start }
            let majority = votes.keys.sorted { votes[$0] == votes[$1] ? $0 < $1 : votes[$0]! > votes[$1]! }.first!
            for j in start...i where assigned[j].cluster != majority && assigned[j].strength < (assigned[j].word.end - assigned[j].word.start) * 0.5 {
                assigned[j].cluster = majority; assigned[j].uncertain = true
            }
            start = i + 1
        }
        var utterances: [ConversationUtterance] = []
        for a in assigned {
            guard let id = ids[a.cluster] else { continue }
            if let last = utterances.last, last.speakerID == id, a.word.start - last.end < 1.5,
               !gaps.contains(where: { $0.at >= last.end && $0.at <= a.word.start }) {
                let i = utterances.count - 1
                utterances[i].text += " " + a.word.word.trimmingCharacters(in: .whitespacesAndNewlines)
                utterances[i].end = a.word.end; utterances[i].uncertain = last.uncertain || a.uncertain
            } else {
                utterances.append(.init(id: "u\(utterances.count)", speakerID: id, start: a.word.start, end: a.word.end, text: a.word.word.trimmingCharacters(in: .whitespacesAndNewlines), uncertain: a.uncertain))
            }
        }
        for i in utterances.indices where utterances[i].end - utterances[i].start < 1 { utterances[i].uncertain = true }
        return Result(speakers: speakers, utterances: utterances, prints: prints)
    }
}

public enum SpeakerIdentifier {
    public static func identify(_ speakers: [ConversationSpeaker], prints: [String: VoicePrint], people: [VoicePerson]) -> [ConversationSpeaker] {
        guard !speakers.isEmpty else { return [] }
        if speakers.contains(where: { $0.nameSource == .user }) {
            let locked = Set(speakers.filter { $0.nameSource == .user }.compactMap(\.personID))
            let free = identify(speakers.filter { $0.nameSource != .user }, prints: prints, people: people.filter { !locked.contains($0.id) })
            return speakers.map { speaker in free.first { $0.id == speaker.id } ?? speaker }
        }
        let people = people.sorted { $0.id < $1.id }
        let scores = speakers.map { speaker in people.map { person in prints[speaker.id].map { SpeakerThresholds.score($0, against: person) } ?? 0 } }
        // Ungarischer Algorithmus mit je einer freien Unbekannt-Spalte pro Cluster.
        let n = speakers.count, m = people.count + n
        var u = Array(repeating: 0.0, count: n + 1), v = Array(repeating: 0.0, count: m + 1)
        var p = Array(repeating: 0, count: m + 1), way = p
        for i in 1...n {
            p[0] = i
            var j0 = 0, minv = Array(repeating: Double.infinity, count: m + 1), used = Array(repeating: false, count: m + 1)
            repeat {
                used[j0] = true
                let i0 = p[j0]
                var delta = Double.infinity, j1 = 0
                for j in 1...m where !used[j] {
                    let score = j <= people.count ? scores[i0 - 1][j - 1] : 0
                    let cost = -(score >= SpeakerThresholds.suggestion ? score : 0) - u[i0] - v[j]
                    if cost < minv[j] { minv[j] = cost; way[j] = j0 }
                    if minv[j] < delta { delta = minv[j]; j1 = j }
                }
                for j in 0...m { if used[j] { u[p[j]] += delta; v[j] -= delta } else { minv[j] -= delta } }
                j0 = j1
            } while p[j0] != 0
            repeat { let j1 = way[j0]; p[j0] = p[j1]; j0 = j1 } while j0 != 0
        }
        var result = speakers
        for j in 1...m where p[j] > 0 && j <= people.count {
            let i = p[j] - 1, person = people[j - 1], score = scores[i][j - 1]
            guard result[i].nameSource != .user else { continue }
            if score >= SpeakerThresholds.match {
                result[i].personID = person.id; result[i].name = person.isOwner ? nil : person.name
                result[i].nameSource = person.isOwner ? .owner : .profile
                if person.isOwner { result[i].colorIndex = 0 }
            } else if score >= SpeakerThresholds.suggestion {
                result[i].suggestion = .init(name: person.isOwner ? "Ich" : person.name, personID: person.id, source: .profile, score: score)
            }
        }
        return result
    }
}
