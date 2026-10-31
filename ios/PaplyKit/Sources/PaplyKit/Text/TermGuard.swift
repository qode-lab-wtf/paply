import Foundation

enum TermGuard {
    static let gap = 0.05
    static func replace(_ text: String, _ pattern: String, _ replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
    static func norm(_ text: String) -> String {
        replace(replace(text.lowercased(), "[^\\p{L}\\p{N} ]", " "), "\\s+", " ").trimmingCharacters(in: .whitespaces)
    }
    static func key(_ text: String) -> String {
        var s = replace(text.lowercased().decomposedStringWithCanonicalMapping, "\\p{M}", "").replacingOccurrences(of: "ß", with: "ss")
        for (a,b) in [("sch","s"),("ch","k"),("ph","f"),("ck","k"),("qu","k"),("th","t"),("dt","t"),("x","ks"),("[vfw]","w"),("[cqg]","k"),("[zs]","s"),("b","p"),("d","t"),("[^a-z]",""),("[aeiouyhj]","")] { s = replace(s,a,b) }
        return replace(s, "(.)\\1+", "$1")
    }
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for (i,x) in a.enumerated() {
            var next = [i+1]
            for (j,y) in b.enumerated() { next.append(min(row[j+1]+1, next[j]+1, row[j]+(x == y ? 0 : 1))) }
            row = next
        }
        return row[b.count]
    }
    static func near(_ term: String, _ text: String) -> Bool {
        if norm(text).contains(norm(term)) { return false }
        let k = key(term), w = norm(text).components(separatedBy: " ")
        let n = norm(term).components(separatedBy: " ").count + 1
        for i in w.indices {
            for length in 1...min(n,w.count-i) {
                let x = key(w[i..<i+length].joined(separator: " "))
                if x.count >= 2 && distance(x,k) <= (k.count >= 4 ? 1 : 0) { return true }
            }
        }
        return false
    }
    static func accept(_ term: String, first: String, second: String, lpFirst: Double?, lpSecond: Double?) -> Bool {
        guard let lpFirst, let lpSecond, lpFirst.isFinite, lpSecond.isFinite else { return false }
        let f = norm(first), s = norm(second), t = norm(term)
        guard !f.contains(t), s.contains(t), lpSecond >= lpFirst-gap else { return false }
        let a = Set(f.components(separatedBy: " ")), b = Set(s.components(separatedBy: " "))
        let n = t.components(separatedBy: " ").count
        return b.subtracting(a).count <= n+1 && a.subtracting(b).count <= n+2
    }
    static func candidates(_ vocabulary: String, _ response: Transcription) -> (terms: [String], prompt: String) {
        let terms = vocabulary.components(separatedBy: CharacterSet(charactersIn: ",;\n\r")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var selected = Array(terms.filter { near($0,response.text ?? "") }.prefix(3))
        let uncertain = selected.isEmpty && (response.segments?.contains { ($0.avgLogprob ?? 0) < -0.5 } ?? false)
        if uncertain {
            for term in terms {
                if WhisperPrompt.estimateTokens((selected + [term]).joined(separator: ", ")) > 90 { break }
                selected.append(term)
            }
        }
        guard let first = selected.first else { return ([], "") }
        return (selected, uncertain ? selected.joined(separator: ", ") : selected.map { "\($0), \($0)." }.joined(separator: " ") + " Hallo \(first).")
    }
}
