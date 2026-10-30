package com.paply.android.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.vector.PathParser
import com.paply.android.ui.theme.PaplyColors as C

/** Original p-head geometry from electron-menubar/brand/mark.svg, including its two cutouts. */
@Composable
fun PaplyMark(modifier: Modifier = Modifier, tint: Color? = null) {
    val paths = remember {
        fun path(data: String) = PathParser().parsePathString(data).toPath()
        val eye = Path().apply { addOval(androidx.compose.ui.geometry.Rect(458f,348f,582f,472f)) }
        val gap = Path().apply { addOval(androidx.compose.ui.geometry.Rect(240f,220f,700f,680f)) }
        val head = path("M256 450a214 214 0 1 0 428 0a214 214 0 1 0 -428 0Z M334 450H334A78 78 0 0 1 412 528V764A78 78 0 0 1 334 842H334A78 78 0 0 1 256 764V528A78 78 0 0 1 334 450Z")
        val beak = path("M529.21 538.93A150 150 0 1 1 729.96 576.91A110 110 0 0 0 529.21 538.93Z")
        Path.combine(PathOperation.Difference, head, eye) to Path.combine(PathOperation.Difference, beak, gap)
    }
    Canvas(modifier) {
        withTransform({ scale(size.width / 600f, size.height / 640f, Offset.Zero); translate(-230f,-220f) }) {
            drawPath(paths.second, tint?.let(::SolidColor) ?: Brush.linearGradient(listOf(Color(0xFFFFE066), Color(0xFFFFA51F)), Offset(550f,300f), Offset(730f,580f)))
            drawPath(paths.first, tint?.let(::SolidColor) ?: Brush.linearGradient(listOf(Color(0xFF7CF29A), C.green), Offset(300f,236f), Offset(470f,842f)))
        }
    }
}
