import Foundation

/// Themen-Symbole ohne PaplyKit (auch für die Widget-Erweiterung): Schlüssel = `TopicIcon.rawValue`
/// (Mac-/Lucide-Name, z. B. "map-pin"). Ersatz-SF-Symbol, solange kein eigenes Glyphen-Set da ist.
/// Eine Stelle für App und Widgets (früher doppelt in ThoughtBridge und der Oberfläche).
enum TopicIconKey {
    static func sfSymbol(_ key: String?) -> String {
        switch key {
        case "sparkles": "sparkles"
        case "lightbulb": "lightbulb"
        case "home": "house"
        case "code": "chevron.left.forwardslash.chevron.right"
        case "map-pin": "mappin"
        case "sun": "sun.max"
        case "moon": "moon"
        case "heart": "heart"
        case "coffee": "cup.and.saucer"
        case "briefcase": "briefcase"
        case "calendar": "calendar"
        case "message-circle": "message"
        case "book": "book"
        case "music": "music.note"
        case "camera": "camera"
        case "leaf": "leaf"
        case "flag": "flag"
        case "circle-help": "questionmark.circle"
        case "pencil": "pencil"
        case "plane": "airplane"
        case "wallet": "creditcard"
        case "users": "person.2"
        case "list": "list.bullet"
        case "zap": "bolt"
        default: "circle.fill"
        }
    }
}
