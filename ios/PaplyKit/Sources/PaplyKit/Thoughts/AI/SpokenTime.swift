import Foundation

/// Gesprochene Uhrzeit in einem Zeitausdruck (`due_hint`), für die Fälligkeit (KONZEPT §6.7).
///
/// `NSDataDetector` liest nur Ziffern („um 8“, „15:30“, „8 pm“). Zahlwörter („um acht Uhr“), „halb drei“, „Viertel nach
/// acht“ und „Mitternacht“ übergeht er (der Tag stimmt, die Zeit bleibt seine Vorgabe 12:00), und eine Tageszeit hinter
/// der Uhrzeit sieht er nicht („um 7 Uhr früh“ → 19:00). Diese Erkennung liest die Uhrzeit selbst und legt sie fest wie
/// der Detektor: 1–7 Uhr ohne Tageszeit = nachmittags („um 3“ → 15:00), mit Tageszeit nach ihr („um 7 Uhr früh“ → 7:00,
/// „abends um 8“ → 20:00).
///
/// Erkannt – mit Ziffern oder Zahlwörtern:
/// - Deutsch: „8 Uhr“, „acht Uhr dreißig“, „8:30“, „8.30 Uhr“, „um 8“, „um acht“, „gegen acht“, „halb drei“, „Viertel
///   nach acht“, „Viertel vor acht“, „dreiviertel acht“, „zehn nach acht“ (nur nach „um“/„gegen“), „24 Uhr“, „Mitternacht“.
/// - Englisch: „at 8“, „at eight thirty“, „8 o'clock“, „8 pm“, „8:30 a.m.“, „half past eight“, „quarter past/to eight“,
///   „ten past eight“, „noon“, „midnight“.
///
/// Nicht: Tageszeiten allein („morgen früh“, „abends“, „Mittag“), Datumsangaben („am 10.11.“, „am achten“, „5th“) und
/// Zahlen ohne Uhrzeit-Signal („in zwei Wochen“).
enum SpokenTime {
    /// Uhrzeit auf der 24-Stunden-Uhr. `hour == 24` = Mitternacht am Ende des Tages (0:00 des Folgetags).
    struct Clock: Equatable, Sendable {
        var hour: Int
        var minute: Int
    }

    struct Found: Equatable, Sendable {
        var clock: Clock
        /// Ziffern außerhalb der Uhrzeit („am 10.11. um 9“): Der Ausdruck nennt ein festes Datum.
        var otherDigits: Bool
    }

    /// Erste gesprochene Uhrzeit im Ausdruck
    static func find(in text: String) -> Found? {
        let tokens = tokenize(text)
        for start in tokens.indices {
            guard let match = clock(at: start, in: tokens) else { continue }
            let otherDigits = tokens.indices.contains { tokens[$0].digits && !match.used.contains($0) }
            return Found(clock: adjusted(match, tokens: tokens), otherDigits: otherDigits)
        }
        return nil
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

    static let englishUnits: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    static let englishTens: [String: Int] = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50]

    struct Number {
        var value: Int
        var length: Int
    }

    /// Grundzahl ab `index` (Ziffern, deutsches oder englisches Zahlwort, „twenty five“). Ordnungszahlen („5th“,
    /// „achten“) zählen nicht.
    static func number(at index: Int, in tokens: [Token]) -> Number? {
        guard tokens.indices.contains(index) else { return nil }
        let token = tokens[index]
        if token.digits {
            guard token.text.count <= 2, let value = Int(token.text) else { return nil }
            if index + 1 < tokens.count, tokens[index + 1].gap.isEmpty, ["st", "nd", "rd", "th"].contains(tokens[index + 1].text) {
                return nil
            }
            return Number(value: value, length: 1)
        }
        if let value = germanCardinals[token.text] { return Number(value: value, length: 1) }
        if let tens = englishTens[token.text] {
            if index + 1 < tokens.count, [" ", "-"].contains(tokens[index + 1].gap),
               let unit = englishUnits[tokens[index + 1].text], (1...9).contains(unit) {
                return Number(value: tens + unit, length: 2)
            }
            return Number(value: tens, length: 1)
        }
        if let value = englishUnits[token.text] { return Number(value: value, length: 1) }
        return nil
    }

    // MARK: Uhrzeit

    struct Match {
        /// Stunde, wie gesprochen (0–24), und Minute
        var hour: Int
        var minute: Int
        /// verbrauchte Wörter
        var used: Range<Int>
        /// „pm“/„am“ direkt dahinter: true = nachmittags, false = vormittags
        var meridiem: Bool?
        /// „halb drei“, „Viertel vor eins“: Stunde auf der 12-Stunden-Uhr (0 = 12)
        var twelveHour = false
    }

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
        case "mitternacht", "midnight":
            return Match(hour: 24, minute: 0, used: start..<(start + 1))
        case "noon", "midday":
            return Match(hour: 12, minute: 0, used: start..<(start + 1))
        case "halb":
            // „halb drei“ = 2:30
            guard let hour = number(at: start + 1, in: tokens), (1...12).contains(hour.value) else { return nil }
            return Match(hour: hour.value - 1, minute: 30, used: start..<(start + 1 + hour.length), twelveHour: true)
        case "viertel", "quarter":
            // „Viertel nach acht“, „Viertel vor acht“, „quarter past/to eight“
            guard let direction = word(tokens, start + 1), ["nach", "vor", "past", "to"].contains(direction),
                  let hour = number(at: start + 2, in: tokens), (1...12).contains(hour.value) else { return nil }
            let after = direction == "nach" || direction == "past"
            return Match(hour: after ? hour.value : hour.value - 1, minute: after ? 15 : 45,
                         used: start..<(start + 2 + hour.length), twelveHour: true)
        case "dreiviertel":
            guard let hour = number(at: start + 1, in: tokens), (1...12).contains(hour.value) else { return nil }
            return Match(hour: hour.value - 1, minute: 45, used: start..<(start + 1 + hour.length), twelveHour: true)
        case "half":
            guard word(tokens, start + 1) == "past", let hour = number(at: start + 2, in: tokens),
                  (1...12).contains(hour.value) else { return nil }
            return Match(hour: hour.value, minute: 30, used: start..<(start + 2 + hour.length), twelveHour: true)
        case "ein" where word(tokens, start + 1) == "uhr":
            return withMeridiem(withMinutes(Match(hour: 1, minute: 0, used: start..<(start + 2)), tokens: tokens), tokens: tokens)
        default:
            break
        }
        // „drei viertel acht“ (= dreiviertel acht)
        if first == "drei", word(tokens, start + 1) == "viertel", let hour = number(at: start + 2, in: tokens),
           (1...12).contains(hour.value) {
            return Match(hour: hour.value - 1, minute: 45, used: start..<(start + 2 + hour.length), twelveHour: true)
        }
        guard let spoken = number(at: start, in: tokens) else { return nil }
        let value = spoken.value
        let next = start + spoken.length
        // „8:30“, „8.30 Uhr“, „um 8.30“ – aber „10.11.“ ist ein Datum
        if tokens[start].digits, next < tokens.count, tokens[next].digits, tokens[next].text.count == 2,
           let minute = Int(tokens[next].text), (0...59).contains(minute), (0...24).contains(value) {
            let separator = tokens[next].gap
            let afterwards = word(tokens, next + 1)
            let dateLike = next + 1 < tokens.count && tokens[next + 1].digits && tokens[next + 1].gap.hasPrefix(".")
            if separator == ":" || (separator == "." && (afterwards == "uhr" || leadIn(before: start, in: tokens)) && !dateLike) {
                let end = afterwards == "uhr" ? next + 2 : next + 1
                return withMeridiem(Match(hour: value, minute: minute, used: start..<end), tokens: tokens)
            }
        }
        // „8 Uhr“, „acht Uhr dreißig“
        if word(tokens, next) == "uhr", (0...24).contains(value) {
            return withMeridiem(withMinutes(Match(hour: value, minute: 0, used: start..<(next + 1)), tokens: tokens), tokens: tokens)
        }
        // „8 o'clock“
        if ["o'clock", "oclock"].contains(word(tokens, next) ?? ""), (1...12).contains(value) {
            return withMeridiem(Match(hour: value, minute: 0, used: start..<(next + 1)), tokens: tokens)
        }
        // „8 pm“, „8pm“, „8 a.m.“
        if (0...12).contains(value), let meridiem = meridiem(at: next, in: tokens) {
            return Match(hour: value, minute: 0, used: start..<(next + meridiem.length), meridiem: meridiem.pm)
        }
        // „zehn nach acht“ (nach „um“/„gegen“), „ten past eight“, „ten to eight“ (nach „at“)
        if (1...29).contains(value), let direction = word(tokens, next), ["nach", "vor", "past", "to"].contains(direction),
           let hour = number(at: next + 1, in: tokens), (1...12).contains(hour.value),
           direction == "past" || leadIn(before: start, in: tokens) {
            let after = direction == "nach" || direction == "past"
            return Match(hour: after ? hour.value : hour.value - 1, minute: after ? value : 60 - value,
                         used: start..<(next + 1 + hour.length), twelveHour: true)
        }
        // „um 8“, „um acht“, „at eight thirty“
        if leadIn(before: start, in: tokens), (0...24).contains(value) {
            return withMeridiem(withMinutes(Match(hour: value, minute: 0, used: start..<next), tokens: tokens), tokens: tokens)
        }
        return nil
    }

    /// Minuten direkt nach der Stunde, nur durch ein Leerzeichen getrennt („acht Uhr dreißig“, „eight thirty“)
    private static func withMinutes(_ match: Match, tokens: [Token]) -> Match {
        let index = match.used.upperBound
        guard tokens.indices.contains(index), tokens[index].gap == " ",
              let minute = number(at: index, in: tokens), (0...59).contains(minute.value) else { return match }
        var result = match
        result.minute = minute.value
        result.used = match.used.lowerBound..<(index + minute.length)
        return result
    }

    private static func withMeridiem(_ match: Match, tokens: [Token]) -> Match {
        guard match.hour <= 12, let meridiem = meridiem(at: match.used.upperBound, in: tokens) else { return match }
        var result = match
        result.meridiem = meridiem.pm
        result.used = match.used.lowerBound..<(match.used.upperBound + meridiem.length)
        return result
    }

    /// „pm“, „am“, „a.m.“/„p.m.“ (als „a“ „m“). „am“ nur direkt an der Zahl („8am“) oder am Ende – sonst ist es das
    /// deutsche „am“ („um 8 am Freitag“).
    private static func meridiem(at index: Int, in tokens: [Token]) -> (pm: Bool, length: Int)? {
        guard let text = word(tokens, index) else { return nil }
        if text == "pm" { return (true, 1) }
        if text == "am", tokens[index].gap.isEmpty || index + 1 == tokens.count { return (false, 1) }
        if ["a", "p"].contains(text), word(tokens, index + 1) == "m", tokens[index + 1].gap == "." {
            return (text == "p", 2)
        }
        return nil
    }

    // MARK: Tageszeit

    static let afternoonWords: Set<String> = ["abend", "abends", "nachmittag", "nachmittags", "evening", "afternoon", "tonight"]
    static let morningWords: Set<String> = ["früh", "morgens", "vormittag", "vormittags", "morning"]
    static let noonWords: Set<String> = ["mittag", "mittags"]
    static let nightWords: Set<String> = ["nacht", "nachts", "night"]

    /// Stunde auf der 24-Stunden-Uhr: nach „am/pm“, sonst nach der Tageszeit im Ausdruck, sonst nach der Regel des
    /// Detektors (1–7 Uhr = nachmittags)
    static func adjusted(_ match: Match, tokens: [Token]) -> Clock {
        var hour = match.hour
        let minute = match.minute
        if hour == 24 { return Clock(hour: 24, minute: 0) }
        if match.twelveHour, hour == 0 { hour = 12 } // „halb eins“ = 12:30
        if let pm = match.meridiem {
            if pm, hour < 12 { hour += 12 }
            if !pm, hour == 12 { hour = 0 }
            return Clock(hour: hour, minute: minute)
        }
        guard (1...12).contains(hour) else { return Clock(hour: hour, minute: minute) }
        let words = Set(tokens.map(\.text))
        if !words.isDisjoint(with: afternoonWords) {
            if hour < 12 { hour += 12 }
        } else if !words.isDisjoint(with: morningWords) {
            // „um 7 Uhr früh“ = 7:00
        } else if !words.isDisjoint(with: noonWords) {
            if hour <= 5 { hour += 12 } // „um 2 Uhr mittags“ = 14:00
        } else if !words.isDisjoint(with: nightWords) {
            if hour == 12 { hour = 0 } else if hour >= 9 { hour += 12 } // „um 11 Uhr nachts“ = 23:00, „um 2 Uhr nachts“ = 2:00
        } else if hour <= 7 {
            hour += 12 // wie der Detektor: „um 3“ = 15:00
        }
        return Clock(hour: hour, minute: minute)
    }
}
