package com.paply.android.thoughts

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.graphics.Rect
import androidx.core.graphics.createBitmap
import com.paply.thoughts.display.TopicImageCodec
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import kotlin.math.roundToInt

/** ImageDecoder applies EXIF orientation. Only freshly drawn sRGB pixels leave this codec. */
class AndroidTopicImageCodec : TopicImageCodec {
    private class Pixels(val bitmap: Bitmap) : TopicImageCodec.Image {
        override val width get() = bitmap.width
        override val height get() = bitmap.height
    }
    override fun dimensions(data: ByteArray): TopicImageCodec.Dimensions? {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, options)
        return if (options.outWidth > 0 && options.outHeight > 0)
            TopicImageCodec.Dimensions(options.outWidth, options.outHeight) else null
    }
    override fun orientedThumbnail(data: ByteArray, maxDimension: Int): TopicImageCodec.Image? = try {
        val source = ImageDecoder.createSource(ByteBuffer.wrap(data))
        Pixels(ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            val scale = minOf(1.0, maxDimension.toDouble() / maxOf(info.size.width, info.size.height))
            decoder.setTargetSize((info.size.width * scale).roundToInt().coerceAtLeast(1),
                (info.size.height * scale).roundToInt().coerceAtLeast(1))
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
        })
    } catch (_: Exception) { null }

    override fun encodeSquareJPEG(image: TopicImageCodec.Image, crop: TopicImageCodec.Crop,
        edge: Int, quality: Double): ByteArray? {
        val source = (image as? Pixels)?.bitmap ?: return null
        val fresh = createBitmap(edge, edge, Bitmap.Config.ARGB_8888)
        return try {
            val canvas = Canvas(fresh)
            canvas.drawColor(Color.WHITE)
            canvas.drawBitmap(source, Rect(crop.x, crop.y, crop.x + crop.side, crop.y + crop.side),
                Rect(0, 0, edge, edge), Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
            ByteArrayOutputStream().use { bytes ->
                if (fresh.compress(Bitmap.CompressFormat.JPEG, (quality.coerceIn(0.0, 1.0) * 100).roundToInt(), bytes))
                    bytes.toByteArray() else null
            }
        } finally { fresh.recycle(); source.recycle() }
    }
}
