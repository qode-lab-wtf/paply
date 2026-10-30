package com.paply.android.ui.thoughts.map

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb

/** Small reusable textures, like the tiled grid/resolved symbols in the iOS Canvas. */
internal fun orbTexture(colors:BubbleColors):ImageBitmap {
    val bitmap=Bitmap.createBitmap(288,288,Bitmap.Config.ARGB_8888)
    val canvas=Canvas(bitmap)
    val paint=Paint(Paint.ANTI_ALIAS_FLAG)
    paint.shader=RadialGradient(144f,144f,144f,intArrayOf(colors.body.copy(alpha=colors.glow).toArgb(),Color.Transparent.toArgb()),null,Shader.TileMode.CLAMP)
    canvas.drawCircle(144f,144f,144f,paint)
    paint.shader=RadialGradient(123.52f,119.68f,108.8f,intArrayOf(colors.light.toArgb(),colors.body.toArgb(),colors.deep.toArgb()),null,Shader.TileMode.CLAMP)
    canvas.drawCircle(144f,144f,64f,paint)
    return bitmap.asImageBitmap()
}

internal fun dotTexture(color:Color):ImageBitmap {
    val bitmap=Bitmap.createBitmap(48,48,Bitmap.Config.ARGB_8888)
    val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply {
        shader=RadialGradient(24f,24f,24f,intArrayOf(color.copy(alpha=.4f).toArgb(),Color.Transparent.toArgb()),null,Shader.TileMode.CLAMP)
    }
    Canvas(bitmap).drawCircle(24f,24f,24f,paint)
    return bitmap.asImageBitmap()
}

internal class MapGridTexture(color:Color) {
    private val bitmap=Bitmap.createBitmap(96,96,Bitmap.Config.ARGB_8888).also {
        Canvas(it).drawCircle(48f,48f,3.6f,Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color=color.toArgb() })
    }
    private val shader=BitmapShader(bitmap,Shader.TileMode.REPEAT,Shader.TileMode.REPEAT)
    private val paint=Paint(Paint.FILTER_BITMAP_FLAG).apply { this.shader=this@MapGridTexture.shader }
    private val matrix=Matrix()
    fun draw(canvas:Canvas,width:Float,height:Float,spacing:Float,x:Float,y:Float) {
        matrix.setScale(spacing/96,spacing/96)
        matrix.postTranslate(x-spacing/2,y-spacing/2)
        shader.setLocalMatrix(matrix)
        canvas.drawRect(0f,0f,width,height,paint)
    }
}
