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
}
