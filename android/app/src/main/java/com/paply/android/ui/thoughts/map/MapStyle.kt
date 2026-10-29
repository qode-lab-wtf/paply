package com.paply.android.ui.thoughts.map

import androidx.compose.runtime.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.geometry.Offset
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.android.ui.thoughts.TopicTint

internal data class MapStyle(val dark: Boolean) {
    val ground = if (dark) C.forest else Color(0xFFF2F3EF)
    val ink = if (dark) C.text else Color(0xFF0F1511)
    val secondary = if (dark) C.secondary else Color(0xFF2B342F).copy(alpha=.64f)
    val tertiary = if (dark) C.tertiary else Color(0xFF2B342F).copy(alpha=.42f)
    val open = if (dark) C.thoughtGold else Color(0xFFC98A12)
    val grid = if (dark) Color.White.copy(alpha=.075f) else Color(0xFF10281A).copy(alpha=.11f)
    val neutral = if (dark) C.text.copy(alpha=.44f) else Color(0xFF2B342F).copy(alpha=.42f)
    fun bubble(tint: TopicTint) = if (dark) BubbleColors(tint.ink, tint.base, lerp(tint.base, Color.Black, .48f),
        Color.White.copy(alpha=.96f), lerp(tint.ink,tint.base,.45f), tint.base, .46f)
    else BubbleColors(lerp(Color.White,tint.ink,.08f), lerp(Color.White,tint.ink,.5f), tint.ink,
        lerp(tint.base, Color.Black,.65f), tint.base, tint.base, .2f)
}
internal data class BubbleColors(val light: Color, val body: Color, val deep: Color, val glyph: Color,
    val dot: Color, val line: Color, val glow: Float)
