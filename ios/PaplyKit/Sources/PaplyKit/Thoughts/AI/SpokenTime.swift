import Foundation

/// Gesprochene Uhrzeit in einem Zeitausdruck (`due_hint`), für die Fälligkeit (KONZEPT §6.7).
///
/// Arbeitsteilung mit `NSDataDetector` (gemessen): Der Detektor versteht Ziffern und Englisch („morgen um 07:00“,
/// „morgen um 15 Uhr“, „at 6 am tomorrow“, „8 pm“). Er übergeht deutsche Wortformen – Zahlwörter („um acht“), „halb
/// drei“, „Viertel vor/nach acht“, „dreiviertel acht“, „zehn nach acht“, „Mitternacht“ – und eine Tageszeit neben der
/// Uhrzeit („morgen um 7 Uhr früh“ → 19:00, „morgen um 2 Uhr nachts“ → 14:00, „morgen abend um 8“ → 17:00).
///
/// Darum legt diese Erkennung die Uhrzeit nur fest (`fixed`), wenn der Ausdruck eine Wortform oder eine Tageszeit
/// enthält – sonst sagt sie nur, ob und welche Ziffern-Uhrzeit dasteht (das Zifferblatt), und die Uhrzeit bleibt beim
/// Detektor (`DueDate.clock`). Englische Wortformen („at eight“, „half past eight pm“, „noon“) erkennt sie nicht.
///
/// Stunde einer festgelegten Uhrzeit:
/// - Tageszeit genannt, sie gilt: früh/morgens 12 → 0 Uhr, vormittags wie gesagt, mittags 1–5 → 13–17 Uhr,
///   nachmittags/abends +12, nachts 12 → 0 Uhr und 9–11 → 21–23 Uhr („um 2 Uhr nachts“ = 2:00)
/// - Wortform ohne Tageszeit: 1–7 Uhr = nachmittags, wie der Detektor bei „um 3“ („halb drei“ = 14:30, „um acht“ = 8:00)
///
/// Nichts Eindeutiges (keine Uhrzeit, zwei Uhrzeiten, zwei verschiedene Tageszeiten) → nil: nichts wird überschrieben.
/// Nicht erkannt: Tageszeiten allein („morgen früh“, „abends“, „Mittag“), Datumsangaben („am 10.11.“, „am achten“,
/// „5th“) und Zahlen ohne Uhrzeit-Signal („in zwei Wochen“).
enum SpokenTime {
    /// Uhrzeit auf der 24-Stunden-Uhr. `hour == 24` = Mitternacht am Ende des Tages (0:00 des Folgetags).
    struct Clock: Equatable, Sendable {
        var hour: Int
        var minute: Int
    }

    struct Found: Equatable, Sendable {
        /// `fixed`: die Uhrzeit nach der Regel oben. Sonst das Zifferblatt, wie es dasteht („15 Uhr“ = 15:00, „8 pm“
        /// = 8:00) – welche Hälfte des Tages, entscheidet der Detektor.
        var clock: Clock
        /// Wortform oder Tageszeit: Diese Erkennung legt die Uhrzeit fest, nicht der Detektor
        var fixed: Bool
        /// Ziffern außerhalb der Uhrzeit („am 10.11. um 9“): Der Ausdruck nennt ein festes Datum.
        var otherDigits: Bool
    }

    /// Die eine Uhrzeit im Ausdruck – nil, wenn keine oder nichts Eindeutiges
    static func find(in text: String) -> Found? {
        let tokens = tokenize(text)
        var matches: [Match] = []
        var index = 0
        while index < tokens.count {
            if let match = clock(at: index, in: tokens) {
                matches.append(match)
                index = match.used.upperBound
            } else {
                index += 1
            }
        }
        guard matches.count == 1, let match = matches.first else { return nil }
        let parts = Set(tokens.compactMap { dayParts[$0.text] })
        guard parts.count <= 1 else { return nil }
        let part = parts.first
        let fixed = match.words || part != nil
        let otherDigits = tokens.indices.contains { tokens[$0].digits && !match.used.contains($0) }
        return Found(clock: fixed ? fixedClock(match, part: part) : Clock(hour: match.hour, minute: match.minute),
                     fixed: fixed, otherDigits: otherDigits)
    }

    /// Liegt `date` genau auf der Uhrzeit? (Mitternacht = 0:00)
    static func matches(_ clock: Clock, date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return parts.hour == clock.hour % 24 && parts.minute == clock.minute
    }

    // MARK: Wörter

    struct Token {
        var text: String
        var digits: Bool
        /// Zeichen zwischen dem vorigen Wort und diesem: „:“ in „8:30“, „“ in „8pm“, sonst meist „ “
        var gap: String
    }

    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentDigits = false
        var gap = ""
        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(Token(text: current, digits: currentDigits, gap: gap))
            current = ""
            gap = ""
        }
        let characters = Array(text.lowercased())
        for (index, character) in characters.enumerated() {
            // Apostroph nur mitten in einem Wort („o'clock“)
            let apostrophe = (character == "'" || character == "’") && !current.isEmpty && !currentDigits
                && index + 1 < characters.count && characters[index + 1].isLetter
            if character.isASCII, character.isNumber {
                if !current.isEmpty, !currentDigits { flush() }
                currentDigits = true
                current.append(character)
            } else if character.isLetter || apostrophe {
                if !current.isEmpty, currentDigits { flush() }
                currentDigits = false
                current.append(apostrophe ? "'" : character)
            } else {
                flush()
                gap.append(character)
            }
        }
        flush()
        return tokens
    }

    // MARK: Zahlen

    static let germanCardinals: [String: Int] = {
        var map: [String: Int] = ["null": 0, "eins": 1]
        let units = ["", "ein", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun"]
        for value in 2...9 { map[units[value]] = value }
        let teens = ["zehn", "elf", "zwölf", "dreizehn", "vierzehn", "fünfzehn", "sechzehn", "siebzehn", "achtzehn", "neunzehn"]
        for (offset, word) in teens.enumerated() { map[word] = 10 + offset }
        for (tens, word) in [(20, "zwanzig"), (30, "dreißig"), (30, "dreissig"), (40, "vierzig"), (50, "fünfzig")] {
            map[word] = tens
            for unit in 1...9 { map[units[unit] + "und" + word] = tens + unit }
        }
        return map
    }()

    struct Number {
        var value: Int
        /// als Zahlwort gesprochen (nicht in Ziffern)
        var word: Bool
    }

    /// Grundzahl in einem Wort: Ziffern (höchstens zwei) oder deutsches Zahlwort. Ordnungszahlen („5th“, „achten“)
    /// zählen nicht.
    static func number(at index: Int, in tokens: [Token]) -> Number? {
        guard tokens.indices.contains(index) else { return nil }
        let token = tokens[index]
        if token.digits {
            guard token.text.count <= 2, let value = Int(token.text) else { return nil }
            if index + 1 < tokens.count, tokens[index + 1].gap.isEmpty, ["st", "nd", "rd", "th"].contains(tokens[index + 1].text) {
                return nil
            }
            return Number(value: value, word: false)
        }
        return germanCardinals[token.text].map { Number(value: $0, word: true) }
    }

    // MARK: Uhrzeit

    struct Match {
        /// Stunde, wie gesprochen (0–24), und Minute
        var hour: Int
        var minute: Int
        /// verbrauchte Wörter
        var used: Range<Int>
        /// Wortform: Zahlwort, „halb“, „Viertel“, „nach/vor“, „Mitternacht“
        var words: Bool
        /// „halb drei“, „Viertel vor eins“: Stunde auf der 12-Stunden-Uhr (0 = 12)
        var twelveHour = false
    }

    /// „at“/„around“ nur, um eine Ziffern-Uhrzeit zu erkennen („tomorrow at 8“) – die Uhrzeit setzt dort der Detektor
    static let leadIns: Set<String> = ["um", "gegen", "at", "around"]

    private static func word(_ tokens: [Token], _ index: Int) -> String? {
        tokens.indices.contains(index) ? tokens[index].text : nil
    }

    private static func leadIn(before index: Int, in tokens: [Token]) -> Bool {
        index > 0 && leadIns.contains(tokens[index - 1].text)
    }

    /// Uhrzeit, die bei `start` beginnt
    static func clock(at start: Int, in tokens: [Token]) -> Match? {
        let first = tokens[start].text
        switch first {
        case "mitternacht":
            return Match(hour: 24, minute: 0, used: start..<(start + 1), words: true)
        case "halb":
            // „halb drei“ = 2:30
            guard let hour = number(at: start + 1, in: tokens), (1...12).contains(hour.value) else { return nil }
            return Match(hour: hour.value - 1, minute: 30, used: start..<(start + 2), words: true, twelveHour: true)
        case "viertel":
            // „Viertel nach acht“, „Viertel vor acht“
            guard let direction = word(tokens, start + 1), ["nach", "vor"].contains(direction),
                  let hour = number(at: start + 2, in: tokens), (1...12).contains(hour.value) else { return nil }
            let after = direction == "nach"
            return Match(hour: after ? hour.value : hour.value - 1, minute: after ? 15 : 45, used: start..<(start + 3),
                         words: true, twelveHour: true)
        case "dreiviertel":
            guard let hour = number(at: start + 1, in: tokens), (1...12).contains(hour.value) else { return nil }
            return Match(hour: hour.value - 1, minute: 45, used: start..<(start + 2), words: true, twelveHour: true)
        case "ein" where word(tokens, start + 1) == "uhr":
            return withMinutes(Match(hour: 1, minute: 0, used: start..<(start + 2), words: true), tokens: tokens)
        default:
            break
        }
        // „drei viertel acht“ (= dreiviertel acht)
        if first == "drei", word(tokens, start + 1) == "viertel", let hour = number(at: start + 2, in: tokens),
           (1...12).contains(hour.value) {
            return Match(hour: hour.value - 1, minute: 45, used: start..<(start + 3), words: true, twelveHour: true)
        }
        guard let spoken = number(at: start, in: tokens) else { return nil }
        let value = spoken.value
        let next = start + 1
        // „8:30“, „8.30 Uhr“, „um 8.30“ – aber „10.11.“ ist ein Datum
        if !spoken.word, next < tokens.count, tokens[next].digits, tokens[next].text.count == 2,
           let minute = Int(tokens[next].text), (0...59).contains(minute), (0...24).contains(value) {
            let separator = tokens[next].gap
            let afterwards = word(tokens, next + 1)
            let dateLike = next + 1 < tokens.count && tokens[next + 1].digits && tokens[next + 1].gap.hasPrefix(".")
            if separator == ":" || (separator == "." && (afterwards == "uhr" || leadIn(before: start, in: tokens)) && !dateLike) {
                let end = afterwards == "uhr" ? next + 2 : next + 1
                return Match(hour: value, minute: minute, used: start..<end, words: false)
            }
        }
        // „8 Uhr“, „acht Uhr dreißig“
        if word(tokens, next) == "uhr", (0...24).contains(value) {
            return withMinutes(Match(hour: value, minute: 0, used: start..<(next + 1), words: spoken.word), tokens: tokens)
        }
        // „zehn nach acht“, „fünf vor zwölf“ – nur nach „um“/„gegen“
        if (1...29).contains(value), let direction = word(tokens, next), ["nach", "vor"].contains(direction),
           let hour = number(at: next + 1, in: tokens), (1...12).contains(hour.value), leadIn(before: start, in: tokens) {
            let after = direction == "nach"
            return Match(hour: after ? hour.value : hour.value - 1, minute: after ? value : 60 - value,
                         used: start..<(next + 2), words: true, twelveHour: true)
        }
        // Ziffern mit englischem Signal: „8 pm“, „8pm“, „8 a.m.“, „8 o'clock“ (Zifferblatt; die Hälfte setzt der Detektor)
        if !spoken.word, (0...12).contains(value), let length = englishSuffix(at: next, in: tokens) {
            return Match(hour: value, minute: 0, used: start..<(next + length), words: false)
        }
        // „um 8“, „um acht“, „gegen acht“, „at 8“
        if leadIn(before: start, in: tokens), (0...24).contains(value) {
            return withMinutes(Match(hour: value, minute: 0, used: start..<next, words: spoken.word), tokens: tokens)
        }
        return nil
    }

    /// Minuten direkt nach der Stunde, nur durch ein Leerzeichen getrennt („acht Uhr dreißig“, „um 8 Uhr 30“)
    private static func withMinutes(_ match: Match, tokens: [Token]) -> Match {
        let index = match.used.upperBound
        guard tokens.indices.contains(index), tokens[index].gap == " ",
              let minute = number(at: index, in: tokens), (0...59).contains(minute.value) else { return match }
        var result = match
        result.minute = minute.value
        result.used = match.used.lowerBound..<(index + 1)
        result.words = match.words || minute.word
        return result
    }

    /// „pm“, „am“ (nur direkt an der Zahl oder am Ende – sonst ist es das deutsche „am“), „a.m.“/„p.m.“, „o'clock“:
    /// Anzahl der Wörter
    private static func englishSuffix(at index: Int, in tokens: [Token]) -> Int? {
        guard let text = word(tokens, index) else { return nil }
        if text == "pm" || text == "o'clock" || text == "oclock" { return 1 }
        if text == "am", tokens[index].gap.isEmpty || index + 1 == tokens.count { return 1 }
        if ["a", "p"].contains(text), word(tokens, index + 1) == "m", tokens[index + 1].gap == "." { return 2 }
        return nil
    }

    // MARK: Tageszeit

    enum DayPart: Sendable {
        /// früh, morgens
        case early
        /// vormittags
        case forenoon
        /// mittags
        case noon
        /// nachmittags, abends
        case evening
        /// nachts
        case night
    }

    /// Nur Deutsch; „morgen“ ist der Tag, nicht die Tageszeit
    static let dayParts: [String: DayPart] = [
        "früh": .early, "morgens": .early,
        "vormittag": .forenoon, "vormittags": .forenoon,
        "mittag": .noon, "mittags": .noon,
        "nachmittag": .evening, "nachmittags": .evening, "abend": .evening, "abends": .evening,
        "nacht": .night, "nachts": .night,
    ]

    /// Stunde auf der 24-Stunden-Uhr: nach der Tageszeit, ohne sie 1–7 Uhr = nachmittags
    static func fixedClock(_ match: Match, part: DayPart?) -> Clock {
        let minute = match.minute
        if match.hour == 24 { return Clock(hour: 24, minute: 0) }
        var hour = match.hour
        if match.twelveHour, hour == 0 { hour = 12 } // „halb eins“ = 12:30
        guard (1...12).contains(hour) else { return Clock(hour: hour, minute: minute) }
        switch part {
        case .early:
            if hour == 12 { hour = 0 } // „halb eins morgens“ = 0:30
        case .forenoon:
            break
        case .noon:
            if hour <= 5 { hour += 12 } // „um 2 Uhr mittags“ = 14:00, „zwölf Uhr mittags“ = 12:00
        case .evening:
            if hour < 12 { hour += 12 }
        case .night:
            if hour == 12 { hour = 0 } else if hour >= 9 { hour += 12 } // „11 Uhr nachts“ = 23:00, „2 Uhr nachts“ = 2:00
        case nil:
            if hour <= 7 { hour += 12 } // wie der Detektor: „um 3“ = 15:00
        }
        return Clock(hour: hour, minute: minute)
    }
}
