package com.paply.android.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Values copied from Shared/Core/Brand.swift and ThoughtsUI.swift; iOS forces dark in both appearances. */
object PaplyColors {
    val green = Color(0xFF22B45F)
    val greenBright = Color(0xFF3AD879)
    val greenDeep = Color(0xFF13803F)
    val forest = Color(0xFF0F2C20)
    val forestDeep = Color(0xFF0A1D15)
    val beak = Color(0xFFFFC233)
    val mint = Color(0xFFE8F8EE)
    val text = Color(0xFFEEF5F0)
    val secondary = text.copy(alpha = 0.62f)
    val tertiary = text.copy(alpha = 0.42f)
    val row = Color.White.copy(alpha = 0.07f)
    val recordTop = Color(0xFF45E086)
    val recordBottom = green
    val recordInk = Color(0xFF05210F)
    val micDot = Color(0xFFFF9F0A)
    val danger = Color(0xFFFF6B5E)
    val thoughtMint = Color(0xFFD8F39A)
    val thoughtLeaf = Color(0xFF7ED957)
    val thoughtLime = Color(0xFFDCE568)
    val thoughtGold = Color(0xFFF5BF50)
    val thoughtPale = Color(0xFFBFEEC4)
    val thoughtSwipe = Color(0xFFB8862B)
    val thoughtFill = Brush.linearGradient(listOf(thoughtMint, thoughtLime, thoughtGold))
}

object PaplySpace {
    val page = 16.dp
    val card = 16.dp
    val section = 24.dp
    val row = 12.dp
    val gap = 10.dp
}

private fun type(size: Int, weight: FontWeight = FontWeight.Normal, line: Int = size + 6) = TextStyle(
    fontFamily = FontFamily.SansSerif, fontSize = size.sp, fontWeight = weight, lineHeight = line.sp,
    letterSpacing = 0.sp, fontFeatureSettings = "tnum",
)

@Composable
fun PaplyTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(primary = PaplyColors.greenBright, onPrimary = PaplyColors.forest,
            secondary = PaplyColors.thoughtMint, background = PaplyColors.forestDeep,
            onBackground = PaplyColors.text, surface = PaplyColors.forest, onSurface = PaplyColors.text,
            surfaceVariant = Color(0xFF234532), onSurfaceVariant = PaplyColors.secondary,
            error = PaplyColors.danger, outline = Color.White.copy(alpha = 0.2f)),
        typography = Typography(displaySmall = type(31, FontWeight.Bold, 37), headlineLarge = type(31, FontWeight.Bold, 37),
            headlineMedium = type(28, FontWeight.Bold, 34), titleLarge = type(20, FontWeight.Bold, 26),
            titleMedium = type(17, FontWeight.SemiBold, 23), titleSmall = type(15, FontWeight.SemiBold, 21),
            bodyLarge = type(17), bodyMedium = type(15), bodySmall = type(13),
            labelLarge = type(15, FontWeight.SemiBold), labelMedium = type(12, FontWeight.SemiBold), labelSmall = type(11)),
        content = { CompositionLocalProvider(LocalContentColor provides PaplyColors.text, content = content) },
    )
}

@Composable
fun PaplyBackground(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    Box(modifier.fillMaxSize().background(PaplyColors.forestDeep).drawBehind {
        drawRect(Brush.radialGradient(listOf(Color(0xFF1D4A35), PaplyColors.forest, Color(0xFF08160F)),
            center = Offset(size.width * 0.5f, size.height * -0.05f), radius = 900.dp.toPx()))
    }, content = content)
}

/** Additional document token from iOS ThoughtDetailView (.title2, 22 pt bold). */
object PaplyThoughtType {
    val documentTitle = TextStyle(fontFamily = FontFamily.SansSerif, fontSize = 22.sp,
        fontWeight = FontWeight.Bold, lineHeight = 28.sp, letterSpacing = 0.sp)
}
