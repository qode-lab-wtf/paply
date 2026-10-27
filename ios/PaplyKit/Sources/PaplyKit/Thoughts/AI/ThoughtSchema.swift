import Foundation

/// Striktes JSON-Schema der Antwort (KONZEPT §6.6). Stil wie Mac `plan.js` (`obj()`: alle Felder
/// Pflicht, `additionalProperties: false`, null über Typ-Liste). Obergrenzen (Anzahl, Längen)
/// prüft `ThoughtValidator` lokal – `maxItems`/`maxLength` sind im strikten Modus unsicher.
public enum ThoughtSchema {
    public static let name = "paply_thought"
    public static let partName = "paply_thought_part"

    /// `symbol`-Enum = Mac `ICONS` (`contracts.js`), damit Themen 1:1 zum Mac passen.
    public static let symbols: [String] = TopicIcon.allCases.map(\.rawValue)

    private static func object(_ properties: [String: Any]) -> [String: Any] {
        ["type": "object", "additionalProperties": false,
         "required": properties.keys.sorted(), "properties": properties]
    }
    private static var string: [String: Any] { ["type": "string"] }
    private static var nullableString: [String: Any] { ["type": ["string", "null"]] }
    private static func enumeration(_ values: [String]) -> [String: Any] { ["type": "string", "enum": values] }
    private static func array(_ items: [String: Any]) -> [String: Any] { ["type": "array", "items": items] }

    static var task: [String: Any] { object(["text": string, "quote": string, "due_hint": nullableString]) }

    /// Schema eines ganzen Gedankens.
    public static var full: [String: Any] {
        object([
            "title": string,
            "clean_text": string,
            "topic": object([
                "choice": enumeration(["existing", "new", "none"]),
                "id": nullableString,
                "new_name": nullableString,
                "symbol": enumeration(symbols),
            ]),
            "tasks": array(task),
            "related": array(object([
                "ref": string,
                "kind": enumeration(["continues", "same_matter", "changes"]),
                "reason": string,
                "confidence": enumeration(["high", "medium", "low"]),
            ])),
        ])
    }

    /// Schema eines Folgeteils im Teile-Modus (nur Text und Aufgaben).
    public static var part: [String: Any] {
        object(["clean_text": string, "tasks": array(task)])
    }

    /// JSON-Bytes eines Schemas (für die Anfrage und die Token-Schätzung).
    package static func data(_ schema: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])) ?? Data()
    }
}
