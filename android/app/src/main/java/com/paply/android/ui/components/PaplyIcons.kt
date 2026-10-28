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

package com.paply.android.ui.components

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

/** Original Lucide paths, parsed once. Transparent fill, 24×24 viewport, round 2-unit strokes. */
object PaplyIcons {
    private fun vector(name: String, vararg paths: String): ImageVector = ImageVector.Builder(
        name = name, defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f,
    ).apply {
        paths.forEach { data -> addPath(pathData = PathParser().parsePathString(data).toNodes(),
            fill = null, stroke = SolidColor(Color.Black), strokeLineWidth = 2f,
            strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round) }
    }.build()
    val MessageCircle by lazy { vector("messageCircle", "M2.992 16.342a2 2 0 0 1 .094 1.167l-1.065 3.29a1 1 0 0 0 1.236 1.168l3.413-.998a2 2 0 0 1 1.099.092 10 10 0 1 0-4.777-4.719") }
    val ListChecks by lazy { vector("listChecks", "M13 5h8", "M13 12h8", "M13 19h8", "m3 17 2 2 4-4", "m3 7 2 2 4-4") }
    val Globe by lazy { vector("globe", "M 2 12 a 10 10 0 1 0 20 0 a 10 10 0 1 0 -20 0", "M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20", "M2 12h20") }
    val BookA by lazy { vector("bookA", "M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H19a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H6.5a1 1 0 0 1 0-5H20", "m8 13 4-7 4 7", "M9.1 11h5.7") }
    val Mic by lazy { vector("mic", "M12 19v3", "M19 10v2a7 7 0 0 1-14 0v-2", "M 12 2 h 0 a 3 3 0 0 1 3 3 v 7 a 3 3 0 0 1 -3 3 h 0 a 3 3 0 0 1 -3 -3 v -7 a 3 3 0 0 1 3 -3 z") }
    val Keyboard by lazy { vector("keyboard", "M10 8h.01", "M12 12h.01", "M14 8h.01", "M16 12h.01", "M18 8h.01", "M6 8h.01", "M7 16h10", "M8 12h.01", "M 4 4 h 16 a 2 2 0 0 1 2 2 v 12 a 2 2 0 0 1 -2 2 h -16 a 2 2 0 0 1 -2 -2 v -12 a 2 2 0 0 1 2 -2 z") }
    val Hammer by lazy { vector("hammer", "m15 12-9.373 9.373a1 1 0 0 1-3.001-3L12 9", "m18 15 4-4", "m21.5 11.5-1.914-1.914A2 2 0 0 1 19 8.172v-.344a2 2 0 0 0-.586-1.414l-1.657-1.657A6 6 0 0 0 12.516 3H9l1.243 1.243A6 6 0 0 1 12 8.485V10l2 2h1.172a2 2 0 0 1 1.414.586L18.5 14.5") }
    val Send by lazy { vector("send", "M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z", "m21.854 2.147-10.94 10.939") }
    val MessageSquare by lazy { vector("messageSquare", "M22 17a2 2 0 0 1-2 2H6.828a2 2 0 0 0-1.414.586l-2.202 2.202A.71.71 0 0 1 2 21.286V5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2z") }
    val Check by lazy { vector("check", "M20 6 9 17l-5-5") }
    val ShieldCheck by lazy { vector("shieldCheck", "M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z", "m9 12 2 2 4-4") }
    val Bell by lazy { vector("bell", "M10.268 21a2 2 0 0 0 3.464 0", "M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326") }
    val FlaskConical by lazy { vector("flaskConical", "M14 2v6a2 2 0 0 0 .245.96l5.51 10.08A2 2 0 0 1 18 22H6a2 2 0 0 1-1.755-2.96l5.51-10.08A2 2 0 0 0 10 8V2", "M6.453 15h11.094", "M8.5 2h7") }
    val KeyRound by lazy { vector("keyRound", "M2.586 17.414A2 2 0 0 0 2 18.828V21a1 1 0 0 0 1 1h3a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h1a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h.172a2 2 0 0 0 1.414-.586l.814-.814a6.5 6.5 0 1 0-4-4z", "M 16 7.5 a 0.5 0.5 0 1 0 1 0 a 0.5 0.5 0 1 0 -1 0") }
    val Clock by lazy { vector("clock", "M12 6v6l4 2", "M 2 12 a 10 10 0 1 0 20 0 a 10 10 0 1 0 -20 0") }
    val Circle by lazy { vector("circle", "M 2 12 a 10 10 0 1 0 20 0 a 10 10 0 1 0 -20 0") }
    val TriangleAlert by lazy { vector("triangleAlert", "m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3", "M12 9v4", "M12 17h.01") }
    val WifiOff by lazy { vector("wifiOff", "M12 20h.01", "M8.5 16.429a5 5 0 0 1 7 0", "M5 12.859a10 10 0 0 1 5.17-2.69", "M19 12.859a10 10 0 0 0-2.007-1.523", "M2 8.82a15 15 0 0 1 4.177-2.643", "M22 8.82a15 15 0 0 0-11.288-3.764", "m2 2 20 20") }
    val Lightbulb by lazy { vector("lightbulb", "M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5", "M9 18h6", "M10 22h4") }
    val CircleQuestionMark by lazy { vector("circleQuestionMark", "M 2 12 a 10 10 0 1 0 20 0 a 10 10 0 1 0 -20 0", "M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3", "M12 17h.01") }
    val AudioLines by lazy { vector("audioLines", "M2 10v3", "M6 6v11", "M10 3v18", "M14 8v7", "M18 5v13", "M22 10v3") }
    val Lock by lazy { vector("lock", "M 5 11 h 14 a 2 2 0 0 1 2 2 v 7 a 2 2 0 0 1 -2 2 h -14 a 2 2 0 0 1 -2 -2 v -7 a 2 2 0 0 1 2 -2 z", "M7 11V7a5 5 0 0 1 10 0v4") }
    val Quote by lazy { vector("quote", "M16 3a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2 1 1 0 0 1 1 1v1a2 2 0 0 1-2 2 1 1 0 0 0-1 1v2a1 1 0 0 0 1 1 6 6 0 0 0 6-6V5a2 2 0 0 0-2-2z", "M5 3a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2 1 1 0 0 1 1 1v1a2 2 0 0 1-2 2 1 1 0 0 0-1 1v2a1 1 0 0 0 1 1 6 6 0 0 0 6-6V5a2 2 0 0 0-2-2z") }

    // Matching 24×24 line glyphs for iOS SF Symbols absent from its Lucide subset.
    val Back by lazy { vector("arrow-left", "m12 19-7-7 7-7", "M5 12h14") }
    val Chevron by lazy { vector("chevron-right", "m9 18 6-6-6-6") }
    val Info by lazy { vector("info", "M2 12a10 10 0 1 0 20 0a10 10 0 1 0-20 0", "M12 16v-4", "M12 8h.01") }
    val Copy by lazy { vector("copy", "M9 9h11v11H9z", "M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1") }
    val Share by lazy { vector("share", "M12 16V3", "m8 7 4-4 4 4", "M20 12v7a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-7") }
    val Settings by lazy { vector("settings", "M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6", "M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915") }

    // Additional original Lucide glyphs from the iOS thoughts interface.
    val Sparkles by lazy { vector("Sparkles", "M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z", "M20 2v4", "M22 4h-4", "M2 20a2 2 0 1 0 4 0a2 2 0 1 0 -4 0") }
    val House by lazy { vector("House", "M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8", "M3 10a2 2 0 0 1 .709-1.528l7-6a2 2 0 0 1 2.582 0l7 6A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z") }
    val CodeXml by lazy { vector("CodeXml", "m18 16 4-4-4-4", "m6 8-4 4 4 4", "m14.5 4-5 16") }
    val MapPin by lazy { vector("MapPin", "M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0", "M9 10a3 3 0 1 0 6 0a3 3 0 1 0 -6 0") }
    val Sun by lazy { vector("Sun", "M8 12a4 4 0 1 0 8 0a4 4 0 1 0 -8 0", "M12 2v2", "M12 20v2", "m4.93 4.93 1.41 1.41", "m17.66 17.66 1.41 1.41", "M2 12h2", "M20 12h2", "m6.34 17.66-1.41 1.41", "m19.07 4.93-1.41 1.41") }
    val Moon by lazy { vector("Moon", "M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803a6 6 0 0 0 8.268 8.268c.344-.215.825-.004.803.401") }
    val Heart by lazy { vector("Heart", "M2 9.5a5.5 5.5 0 0 1 9.591-3.676.56.56 0 0 0 .818 0A5.49 5.49 0 0 1 22 9.5c0 2.29-1.5 4-3 5.5l-5.492 5.313a2 2 0 0 1-3 .019L5 15c-1.5-1.5-3-3.2-3-5.5") }
    val Coffee by lazy { vector("Coffee", "M10 2v2", "M14 2v2", "M16 8a1 1 0 0 1 1 1v8a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4V9a1 1 0 0 1 1-1h14a4 4 0 1 1 0 8h-1", "M6 2v2") }
    val BriefcaseBusiness by lazy { vector("BriefcaseBusiness", "M12 12h.01", "M16 6V4a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2", "M22 13a18.15 18.15 0 0 1-20 0", "M4 6h16a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-10a2 2 0 0 1 2 -2z") }
    val CalendarDays by lazy { vector("CalendarDays", "M8 2v4", "M16 2v4", "M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2z", "M3 10h18", "M8 14h.01", "M12 14h.01", "M16 14h.01", "M8 18h.01", "M12 18h.01", "M16 18h.01") }
    val BookOpen by lazy { vector("BookOpen", "M12 7v14", "M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z") }
    val Music by lazy { vector("Music", "M9 18V5l12-2v13", "M3 18a3 3 0 1 0 6 0a3 3 0 1 0 -6 0", "M15 16a3 3 0 1 0 6 0a3 3 0 1 0 -6 0") }
    val Camera by lazy { vector("Camera", "M13.997 4a2 2 0 0 1 1.76 1.05l.486.9A2 2 0 0 0 18.003 7H20a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h1.997a2 2 0 0 0 1.759-1.048l.489-.904A2 2 0 0 1 10.004 4z", "M9 13a3 3 0 1 0 6 0a3 3 0 1 0 -6 0") }
    val Leaf by lazy { vector("Leaf", "M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10Z", "M2 21c0-3 1.85-5.36 5.08-6C9.5 14.52 12 13 13 12") }
    val Flag by lazy { vector("Flag", "M4 22V4a1 1 0 0 1 .4-.8A6 6 0 0 1 8 2c3 0 5 2 7.333 2q2 0 3.067-.8A1 1 0 0 1 20 4v10a1 1 0 0 1-.4.8A6 6 0 0 1 16 16c-3 0-5-2-8-2a6 6 0 0 0-4 1.528") }
    val Pencil by lazy { vector("Pencil", "M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z", "m15 5 4 4") }
    val Plane by lazy { vector("Plane", "M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z") }
    val Wallet by lazy { vector("Wallet", "M19 7V4a1 1 0 0 0-1-1H5a2 2 0 0 0 0 4h15a1 1 0 0 1 1 1v4h-3a2 2 0 0 0 0 4h3a1 1 0 0 0 1-1v-2a1 1 0 0 0-1-1", "M3 5v14a2 2 0 0 0 2 2h15a1 1 0 0 0 1-1v-4") }
    val Users by lazy { vector("Users", "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2", "M16 3.128a4 4 0 0 1 0 7.744", "M22 21v-2a4 4 0 0 0-3-3.87", "M5 7a4 4 0 1 0 8 0a4 4 0 1 0 -8 0") }
    val List by lazy { vector("List", "M3 5h.01", "M3 12h.01", "M3 19h.01", "M8 5h13", "M8 12h13", "M8 19h13") }
    val Zap by lazy { vector("Zap", "M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z") }
    val CircleDashed by lazy { vector("CircleDashed", "M10.1 2.182a10 10 0 0 1 3.8 0", "M13.9 21.818a10 10 0 0 1-3.8 0", "M17.609 3.721a10 10 0 0 1 2.69 2.7", "M2.182 13.9a10 10 0 0 1 0-3.8", "M20.279 17.609a10 10 0 0 1-2.7 2.69", "M21.818 10.1a10 10 0 0 1 0 3.8", "M3.721 6.391a10 10 0 0 1 2.7-2.69", "M6.391 20.279a10 10 0 0 1-2.69-2.7") }
    val Tag by lazy { vector("Tag", "M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z", "M7 7.5a0.5 0.5 0 1 0 1 0a0.5 0.5 0 1 0 -1 0") }
    val Hourglass by lazy { vector("Hourglass", "M5 22h14", "M5 2h14", "M17 22v-4.172a2 2 0 0 0-.586-1.414L12 12l-4.414 4.414A2 2 0 0 0 7 17.828V22", "M7 2v4.172a2 2 0 0 0 .586 1.414L12 12l4.414-4.414A2 2 0 0 0 17 6.172V2") }
    val CornerDownRight by lazy { vector("CornerDownRight", "m15 10 5 5-5 5", "M4 4v7a4 4 0 0 0 4 4h12") }
    val Link by lazy { vector("Link", "M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71", "M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71") }
    val ToggleRight by lazy { vector("ToggleRight", "M12 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0", "M9 5h6a7 7 0 0 1 7 7v0a7 7 0 0 1 -7 7h-6a7 7 0 0 1 -7 -7v-0a7 7 0 0 1 7 -7z") }
    val CircleDot by lazy { vector("CircleDot", "M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0", "M11 12a1 1 0 1 0 2 0a1 1 0 1 0 -2 0") }
    val Loader by lazy { vector("Loader", "M21 12a9 9 0 1 1-6.219-8.56") }
    val Merge by lazy { vector("Merge", "m8 6 4-4 4 4", "M12 2v10.3a4 4 0 0 1-1.172 2.872L4 22", "m20 22-5-5") }
    val CirclePlus by lazy { vector("CirclePlus", "M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0", "M8 12h8", "M12 8v8") }
    val VolumeOff by lazy { vector("VolumeOff", "M16 9a5 5 0 0 1 .95 2.293", "M19.364 5.636a9 9 0 0 1 1.889 9.96", "m2 2 20 20", "m7 7-.587.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298V11", "M9.828 4.172A.686.686 0 0 1 11 4.657v.686") }
    val MicOff by lazy { vector("MicOff", "M12 19v3", "M15 9.34V5a3 3 0 0 0-5.68-1.33", "M16.95 16.95A7 7 0 0 1 5 12v-2", "M18.89 13.23A7 7 0 0 0 19 12v-2", "m2 2 20 20", "M9 9v3a3 3 0 0 0 5.12 2.12") }
    val More by lazy { vector("more", "M5 12h.01", "M12 12h.01", "M19 12h.01") }
    val Search by lazy { vector("search", "M21 21l-4.34-4.34", "M3 10a7 7 0 1 0 14 0a7 7 0 1 0-14 0") }
    val Trash by lazy { vector("trash", "M3 6h18", "M9 6V4h6v2", "M5 6l1 14h12l1-14", "M10 10v6", "M14 10v6") }
    val Close by lazy { vector("close", "M6 6l12 12", "M6 18L18 6") }
}
