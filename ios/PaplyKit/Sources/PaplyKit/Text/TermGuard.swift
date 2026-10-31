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
    static let spellingRatio = 0.6
    static func plain(_ text: String) -> String {
        replace(text.decomposedStringWithCanonicalMapping, "\\p{M}", "").replacingOccurrences(of: " ", with: "")
    }
    // Lazy window cache shared by every vocabulary entry for this text.
    final class Windows {
        let words: [String]
        var cache: [Int: (String, String)] = [:]
        init(_ text: String) { words = norm(text).components(separatedBy: " ") }
        func get(_ i: Int, _ length: Int) -> (String, String) {
            let id = i * (words.count + 1) + length
            if let value = cache[id] { return value }
            let text = words[i..<i+length].joined(separator: " ")
            let value = (key(text), plain(text))
            cache[id] = value
            return value
        }
    }
    // Phonetic tolerance is at most one edit; avoid a full edit-distance matrix.
    static func soundMatch(_ x: String, _ k: String) -> Bool {
        if x == k { return true }
        guard k.utf8.count >= 4, abs(x.utf8.count-k.utf8.count) <= 1 else { return false }
        let a = Array(x.utf8), b = Array(k.utf8)
        var i = 0, j = 0, edits = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { i += 1; j += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if a.count >= b.count { i += 1 }
            if b.count >= a.count { j += 1 }
        }
        return edits + (a.count-i) + (b.count-j) <= 1
    }
    static func window(_ term: String, _ cache: Windows) -> (i: Int, length: Int)? {
        let t = norm(term), k = key(term), p = plain(t)
        guard k.count >= 3, !(" " + cache.words.joined(separator: " ") + " ").contains(" " + t + " ") else { return nil }
        let n = t.components(separatedBy: " ").count + 1
        let limit = Int(ceil(Double(p.count) * spellingRatio))
        for i in cache.words.indices {
            for length in 1...min(n, cache.words.count-i) {
                let (x, spelling) = cache.get(i, length)
                if x.count >= 3 && soundMatch(x,k)
                    && distance(spelling,p) <= limit { return (i,length) }
            }
        }
        return nil
    }
    static func near(_ term: String, _ text: String) -> Bool { window(term, Windows(text)) != nil }
    static func accept(_ term: String, first: String, second: String, lpFirst: Double?, lpSecond: Double?) -> Bool {
        guard let lpFirst, let lpSecond, lpFirst.isFinite, lpSecond.isFinite, lpSecond >= lpFirst-gap else { return false }
        let cache = Windows(first), t = norm(term), s = " " + norm(second) + " "
        guard s.contains(" " + t + " "), let win = window(term, cache) else { return false }
        let f = cache.words
        let rest = Array(f[..<win.i]) + Array(f[(win.i+win.length)...])
        let parts = s.components(separatedBy: " " + t + " ")
        guard parts.count <= 2 || rest.count >= 3 else { return false }
        var left = parts.joined(separator: " ").split(separator: " ").map(String.init)
        var gone: [String] = []
        for word in rest {
            if let index = left.firstIndex(of: word) { left.remove(at: index) } else { gone.append(word) }
        }
        let allow = rest.count / 10
        if gone.count <= allow && left.count <= allow { return true }
        let before = win.i > 0 ? f[win.i-1] : ""
        let after = win.i+win.length < f.count ? f[win.i+win.length] : ""
        return gone.count == allow+1 && left.count <= allow && rest.count >= 4 && (gone.contains(before) || gone.contains(after))
    }
    static func candidates(_ vocabulary: String, _ response: Transcription) -> (terms: [String], prompt: String) {
        let cache = Windows(response.text ?? "")
        let terms = vocabulary.components(separatedBy: CharacterSet(charactersIn: ",;\n\r")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let selected = Array(terms.lazy.filter { window($0,cache) != nil }.prefix(3))
        return (selected, selected.map { "\($0), \($0)." }.joined(separator: " "))
    }
}
