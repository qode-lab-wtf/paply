// Linien-Symbole aus Lucide v0.561.0 (https://lucide.dev) – dieselbe Fassung wie die Mac-Notes
// (`electron-menubar/src/apps/notes/icons.tsx`). Erzeugt mit einem Skript aus `lucide-react`; die Pfade
// sind unverändert (24 × 24, Strich 2, runde Enden).
//
// ISC License – Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2023 as part of
// Feather (MIT). All other copyright (c) for Lucide are held by Lucide Contributors 2025.
// Permission to use, copy, modify, and/or distribute this software for any purpose with or without
// fee is hereby granted, provided that the above copyright notice and this permission notice appear
// in all copies. THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD
// TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS.
// (Feather: MIT License, Copyright (c) 2013-2023 Cole Bemis.)

import CoreGraphics

enum Lucide: CaseIterable, Sendable {
    case sparkles, lightbulb, house, codeXml, mapPin, sun, moon, heart, coffee, briefcaseBusiness, calendarDays, messageCircle, bookOpen, music, camera, leaf, flag, circleQuestionMark, pencil, plane, wallet, users, list, zap, listChecks, circleDashed, tag, wifiOff, keyRound, hourglass, triangleAlert, quote, cornerDownRight, link, circle, lock, toggleRight, circleDot, clock, audioLines, loader, merge, circlePlus, volumeOff, micOff, globe, bookA, mic, keyboard, hammer, send, messageSquare, check, shieldCheck, bell

    /// Lucide-Name (zum Abgleich mit lucide.dev)
    var name: String {
        switch self {
        case .sparkles: "sparkles"
        case .lightbulb: "lightbulb"
        case .house: "house"
        case .codeXml: "code-xml"
        case .mapPin: "map-pin"
        case .sun: "sun"
        case .moon: "moon"
        case .heart: "heart"
        case .coffee: "coffee"
        case .briefcaseBusiness: "briefcase-business"
        case .calendarDays: "calendar-days"
        case .messageCircle: "message-circle"
        case .bookOpen: "book-open"
        case .music: "music"
        case .camera: "camera"
        case .leaf: "leaf"
        case .flag: "flag"
        case .circleQuestionMark: "circle-question-mark"
        case .pencil: "pencil"
        case .plane: "plane"
        case .wallet: "wallet"
        case .users: "users"
        case .list: "list"
        case .zap: "zap"
        case .listChecks: "list-checks"
        case .circleDashed: "circle-dashed"
        case .tag: "tag"
        case .wifiOff: "wifi-off"
        case .keyRound: "key-round"
        case .hourglass: "hourglass"
        case .triangleAlert: "triangle-alert"
        case .quote: "quote"
        case .cornerDownRight: "corner-down-right"
        case .link: "link"
        case .circle: "circle"
        case .lock: "lock"
        case .toggleRight: "toggle-right"
        case .circleDot: "circle-dot"
        case .clock: "clock"
        case .audioLines: "audio-lines"
        case .loader: "loader-circle"
        case .merge: "merge"
        case .circlePlus: "circle-plus"
        case .volumeOff: "volume-off"
        case .micOff: "mic-off"
        case .globe: "globe"
        case .bookA: "book-a"
        case .mic: "mic"
        case .keyboard: "keyboard"
        case .hammer: "hammer"
        case .send: "send"
        case .messageSquare: "message-square"
        case .check: "check"
        case .shieldCheck: "shield-check"
        case .bell: "bell"
        }
    }

    /// Bausteine im 24 × 24-Raster, wörtlich aus Lucide
    var elements: [LucideElement] {
        switch self {
        case .sparkles: [.path("M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z"), .path("M20 2v4"), .path("M22 4h-4"), .circle(4, 20, 2)]
        case .lightbulb: [.path("M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5"), .path("M9 18h6"), .path("M10 22h4")]
        case .house: [.path("M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"), .path("M3 10a2 2 0 0 1 .709-1.528l7-6a2 2 0 0 1 2.582 0l7 6A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z")]
        case .codeXml: [.path("m18 16 4-4-4-4"), .path("m6 8-4 4 4 4"), .path("m14.5 4-5 16")]
        case .mapPin: [.path("M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0"), .circle(12, 10, 3)]
        case .sun: [.circle(12, 12, 4), .path("M12 2v2"), .path("M12 20v2"), .path("m4.93 4.93 1.41 1.41"), .path("m17.66 17.66 1.41 1.41"), .path("M2 12h2"), .path("M20 12h2"), .path("m6.34 17.66-1.41 1.41"), .path("m19.07 4.93-1.41 1.41")]
        case .moon: [.path("M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803a6 6 0 0 0 8.268 8.268c.344-.215.825-.004.803.401")]
        case .heart: [.path("M2 9.5a5.5 5.5 0 0 1 9.591-3.676.56.56 0 0 0 .818 0A5.49 5.49 0 0 1 22 9.5c0 2.29-1.5 4-3 5.5l-5.492 5.313a2 2 0 0 1-3 .019L5 15c-1.5-1.5-3-3.2-3-5.5")]
        case .coffee: [.path("M10 2v2"), .path("M14 2v2"), .path("M16 8a1 1 0 0 1 1 1v8a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4V9a1 1 0 0 1 1-1h14a4 4 0 1 1 0 8h-1"), .path("M6 2v2")]
        case .briefcaseBusiness: [.path("M12 12h.01"), .path("M16 6V4a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2"), .path("M22 13a18.15 18.15 0 0 1-20 0"), .rect(2, 6, 20, 14, 2, 2)]
        case .calendarDays: [.path("M8 2v4"), .path("M16 2v4"), .rect(3, 4, 18, 18, 2, 2), .path("M3 10h18"), .path("M8 14h.01"), .path("M12 14h.01"), .path("M16 14h.01"), .path("M8 18h.01"), .path("M12 18h.01"), .path("M16 18h.01")]
        case .messageCircle: [.path("M2.992 16.342a2 2 0 0 1 .094 1.167l-1.065 3.29a1 1 0 0 0 1.236 1.168l3.413-.998a2 2 0 0 1 1.099.092 10 10 0 1 0-4.777-4.719")]
        case .bookOpen: [.path("M12 7v14"), .path("M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z")]
        case .music: [.path("M9 18V5l12-2v13"), .circle(6, 18, 3), .circle(18, 16, 3)]
        case .camera: [.path("M13.997 4a2 2 0 0 1 1.76 1.05l.486.9A2 2 0 0 0 18.003 7H20a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h1.997a2 2 0 0 0 1.759-1.048l.489-.904A2 2 0 0 1 10.004 4z"), .circle(12, 13, 3)]
        case .leaf: [.path("M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10Z"), .path("M2 21c0-3 1.85-5.36 5.08-6C9.5 14.52 12 13 13 12")]
        case .flag: [.path("M4 22V4a1 1 0 0 1 .4-.8A6 6 0 0 1 8 2c3 0 5 2 7.333 2q2 0 3.067-.8A1 1 0 0 1 20 4v10a1 1 0 0 1-.4.8A6 6 0 0 1 16 16c-3 0-5-2-8-2a6 6 0 0 0-4 1.528")]
        case .circleQuestionMark: [.circle(12, 12, 10), .path("M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"), .path("M12 17h.01")]
        case .pencil: [.path("M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"), .path("m15 5 4 4")]
        case .plane: [.path("M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z")]
        case .wallet: [.path("M19 7V4a1 1 0 0 0-1-1H5a2 2 0 0 0 0 4h15a1 1 0 0 1 1 1v4h-3a2 2 0 0 0 0 4h3a1 1 0 0 0 1-1v-2a1 1 0 0 0-1-1"), .path("M3 5v14a2 2 0 0 0 2 2h15a1 1 0 0 0 1-1v-4")]
        case .users: [.path("M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"), .path("M16 3.128a4 4 0 0 1 0 7.744"), .path("M22 21v-2a4 4 0 0 0-3-3.87"), .circle(9, 7, 4)]
        case .list: [.path("M3 5h.01"), .path("M3 12h.01"), .path("M3 19h.01"), .path("M8 5h13"), .path("M8 12h13"), .path("M8 19h13")]
        case .zap: [.path("M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z")]
        case .listChecks: [.path("M13 5h8"), .path("M13 12h8"), .path("M13 19h8"), .path("m3 17 2 2 4-4"), .path("m3 7 2 2 4-4")]
        case .circleDashed: [.path("M10.1 2.182a10 10 0 0 1 3.8 0"), .path("M13.9 21.818a10 10 0 0 1-3.8 0"), .path("M17.609 3.721a10 10 0 0 1 2.69 2.7"), .path("M2.182 13.9a10 10 0 0 1 0-3.8"), .path("M20.279 17.609a10 10 0 0 1-2.7 2.69"), .path("M21.818 10.1a10 10 0 0 1 0 3.8"), .path("M3.721 6.391a10 10 0 0 1 2.7-2.69"), .path("M6.391 20.279a10 10 0 0 1-2.69-2.7")]
        case .tag: [.path("M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z"), .circle(7.5, 7.5, 0.5)]
        case .wifiOff: [.path("M12 20h.01"), .path("M8.5 16.429a5 5 0 0 1 7 0"), .path("M5 12.859a10 10 0 0 1 5.17-2.69"), .path("M19 12.859a10 10 0 0 0-2.007-1.523"), .path("M2 8.82a15 15 0 0 1 4.177-2.643"), .path("M22 8.82a15 15 0 0 0-11.288-3.764"), .path("m2 2 20 20")]
        case .keyRound: [.path("M2.586 17.414A2 2 0 0 0 2 18.828V21a1 1 0 0 0 1 1h3a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h1a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h.172a2 2 0 0 0 1.414-.586l.814-.814a6.5 6.5 0 1 0-4-4z"), .circle(16.5, 7.5, 0.5)]
        case .hourglass: [.path("M5 22h14"), .path("M5 2h14"), .path("M17 22v-4.172a2 2 0 0 0-.586-1.414L12 12l-4.414 4.414A2 2 0 0 0 7 17.828V22"), .path("M7 2v4.172a2 2 0 0 0 .586 1.414L12 12l4.414-4.414A2 2 0 0 0 17 6.172V2")]
        case .triangleAlert: [.path("m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"), .path("M12 9v4"), .path("M12 17h.01")]
        case .quote: [.path("M16 3a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2 1 1 0 0 1 1 1v1a2 2 0 0 1-2 2 1 1 0 0 0-1 1v2a1 1 0 0 0 1 1 6 6 0 0 0 6-6V5a2 2 0 0 0-2-2z"), .path("M5 3a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2 1 1 0 0 1 1 1v1a2 2 0 0 1-2 2 1 1 0 0 0-1 1v2a1 1 0 0 0 1 1 6 6 0 0 0 6-6V5a2 2 0 0 0-2-2z")]
        case .cornerDownRight: [.path("m15 10 5 5-5 5"), .path("M4 4v7a4 4 0 0 0 4 4h12")]
        case .link: [.path("M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"), .path("M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71")]
        case .circle: [.circle(12, 12, 10)]
        case .lock: [.rect(3, 11, 18, 11, 2, 2), .path("M7 11V7a5 5 0 0 1 10 0v4")]
        case .toggleRight: [.circle(15, 12, 3), .rect(2, 5, 20, 14, 7, 7)]
        case .circleDot: [.circle(12, 12, 10), .circle(12, 12, 1)]
        case .clock: [.path("M12 6v6l4 2"), .circle(12, 12, 10)]
        case .audioLines: [.path("M2 10v3"), .path("M6 6v11"), .path("M10 3v18"), .path("M14 8v7"), .path("M18 5v13"), .path("M22 10v3")]
        case .loader: [.path("M21 12a9 9 0 1 1-6.219-8.56")]
        case .merge: [.path("m8 6 4-4 4 4"), .path("M12 2v10.3a4 4 0 0 1-1.172 2.872L4 22"), .path("m20 22-5-5")]
        case .circlePlus: [.circle(12, 12, 10), .path("M8 12h8"), .path("M12 8v8")]
        case .volumeOff: [.path("M16 9a5 5 0 0 1 .95 2.293"), .path("M19.364 5.636a9 9 0 0 1 1.889 9.96"), .path("m2 2 20 20"), .path("m7 7-.587.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298V11"), .path("M9.828 4.172A.686.686 0 0 1 11 4.657v.686")]
        case .micOff: [.path("M12 19v3"), .path("M15 9.34V5a3 3 0 0 0-5.68-1.33"), .path("M16.95 16.95A7 7 0 0 1 5 12v-2"), .path("M18.89 13.23A7 7 0 0 0 19 12v-2"), .path("m2 2 20 20"), .path("M9 9v3a3 3 0 0 0 5.12 2.12")]
        case .globe: [.circle(12, 12, 10), .path("M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"), .path("M2 12h20")]
        case .bookA: [.path("M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H19a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H6.5a1 1 0 0 1 0-5H20"), .path("m8 13 4-7 4 7"), .path("M9.1 11h5.7")]
        case .mic: [.path("M12 19v3"), .path("M19 10v2a7 7 0 0 1-14 0v-2"), .rect(9, 2, 6, 13, 3, 3)]
        case .keyboard: [.path("M10 8h.01"), .path("M12 12h.01"), .path("M14 8h.01"), .path("M16 12h.01"), .path("M18 8h.01"), .path("M6 8h.01"), .path("M7 16h10"), .path("M8 12h.01"), .rect(2, 4, 20, 16, 2, 2)]
        case .hammer: [.path("m15 12-9.373 9.373a1 1 0 0 1-3.001-3L12 9"), .path("m18 15 4-4"), .path("m21.5 11.5-1.914-1.914A2 2 0 0 1 19 8.172v-.344a2 2 0 0 0-.586-1.414l-1.657-1.657A6 6 0 0 0 12.516 3H9l1.243 1.243A6 6 0 0 1 12 8.485V10l2 2h1.172a2 2 0 0 1 1.414.586L18.5 14.5")]
        case .send: [.path("M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z"), .path("m21.854 2.147-10.94 10.939")]
        case .messageSquare: [.path("M22 17a2 2 0 0 1-2 2H6.828a2 2 0 0 0-1.414.586l-2.202 2.202A.71.71 0 0 1 2 21.286V5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2z")]
        case .check: [.path("M20 6 9 17l-5-5")]
        case .shieldCheck: [.path("M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"), .path("m9 12 2 2 4-4")]
        case .bell: [.path("M10.268 21a2 2 0 0 0 3.464 0"), .path("M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326")]
        }
    }
}
