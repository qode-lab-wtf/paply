import Foundation

/// Beispielsatz mit Sprachwechsel für den Whisper-`prompt`.
///
/// Befund der Mac-Messung (ios/docs/phase0/latenz-mac.md): Whisper legt pro Anfrage eine
/// Sprache fest. Ein kurzer englischer Satz mitten in einem deutschen (oder französischen)
/// Diktat wird dann stillschweigend weggelassen oder sogar übersetzt – ohne Lücke in den
/// Zeitstempeln. Zeigt der Prompt einen Sprachwechsel mitten im Satz, transkribiert
/// Whisper beide Sprachen wörtlich.
///
/// Der Inhalt ist entscheidend (gemessen): Ein Alltagsbeispiel („Ich gehe einkaufen, and
/// then I'll call you“) ließ v3 englische Passagen wieder übersetzen. Ein kurzes
/// Arbeits-Update wirkte zuverlässig. Es enthält bewusst keine Fachwörter wie
/// „Deployment“/„Build“, die Whisper in andere Diktate tragen könnte. Gesendet wird nur,
/// wenn mindestens zwei Sprachen des Nutzers einen Satz haben – sonst gibt es keinen
/// passenden Wechsel, den das Beispiel zeigen könnte.
enum CodeSwitchPrimer {
    /// Satzanfänge (`open`) und -enden (`close`) je Sprache.
    static let phrases: [String: (open: [String], close: [String])] = [
        "de": (["Kurzes Update: Das Meeting ist verschoben", "Ich schreibe dir später"],
               ["und der neue Termin ist nächsten Freitag", "bis morgen"]),
        "en": (["Quick update: the meeting has been moved", "I'll write to you later"],
               ["and the new date is next Friday", "see you tomorrow"]),
        "fr": (["Petit point : la réunion est reportée", "Je t'écris plus tard"],
               ["et la nouvelle date est vendredi prochain", "à demain"]),
        "es": (["Breve novedad: la reunión se aplaza", "Te escribo luego"],
               ["y la nueva fecha es el viernes", "hasta mañana"]),
        "it": (["Breve aggiornamento: la riunione è spostata", "Ti scrivo dopo"],
               ["e la nuova data è venerdì prossimo", "a domani"]),
        "pt": (["Novidade rápida: a reunião foi adiada", "Te escrevo depois"],
               ["e a nova data é sexta-feira", "até amanhã"]),
        "nl": (["Korte update: de vergadering is verplaatst", "Ik schrijf je later"],
               ["en de nieuwe datum is volgende vrijdag", "tot morgen"]),
        "tr": (["Kısa bilgi: toplantı ertelendi", "Sana sonra yazarım"],
               ["ve yeni tarih cuma", "yarın görüşürüz"]),
        "pl": (["Krótko: spotkanie jest przełożone", "Napiszę później"],
               ["a nowy termin to piątek", "do jutra"]),
    ]

    /// Die ersten zwei Nutzersprachen mit Beispielsatz; nil, wenn es keine zwei gibt.
    static func pair(_ languages: [String]) -> (String, String)? {
        var codes: [String] = []
        for language in languages {
            let code = baseCode(language)
            if phrases[code] != nil, !codes.contains(code) { codes.append(code) }
        }
        return codes.count >= 2 ? (codes[0], codes[1]) : nil
    }

    static func text(languages: [String]) -> String? {
        guard let (first, second) = pair(languages), let a = phrases[first], let b = phrases[second] else { return nil }
        return "\(a.open[0]), \(b.close[0]). \(a.open[1]), \(b.close[1])."
    }

    static func baseCode(_ identifier: String) -> String {
        identifier.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
    }

    /// Sprachen des Nutzers: Einstellung, sonst die Gerätesprachen.
    static func userLanguages(_ settings: PaplySettings) -> [String] {
        var list = settings.spokenLanguages
        if let fixed = settings.language, !fixed.isEmpty { list.insert(fixed, at: 0) }
        return list.isEmpty ? Locale.preferredLanguages : list
    }
}
