package com.paply.thoughts

import com.paply.thoughts.display.TopicImageCodec
import java.awt.Color
import java.awt.RenderingHints
import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.imageio.IIOImage
import javax.imageio.ImageIO
import javax.imageio.ImageWriteParam

/**
 * Test-only JVM adapter. Production :thoughts never links java.awt/ImageIO; Android supplies
 * Bitmap.
 */
internal object JvmTopicImageCodec : TopicImageCodec {
    private data class Bitmap(val bitmap: BufferedImage) : TopicImageCodec.Image {
        override val width
            get() = bitmap.width

        override val height
            get() = bitmap.height
    }

    override fun dimensions(data: ByteArray): TopicImageCodec.Dimensions? =
        decode(data)?.let { TopicImageCodec.Dimensions(it.width, it.height) }

    private fun decode(data: ByteArray) = runCatching {
        ImageIO.read(ByteArrayInputStream(data))
    }
        .getOrNull()

    override fun orientedThumbnail(data: ByteArray, maxDimension: Int): TopicImageCodec.Image? {
        val image = decode(data) ?: return null
        val ratio = minOf(1.0, maxDimension.toDouble() / maxOf(image.width, image.height))
        val scaled =
            BufferedImage(
                maxOf(1, (image.width * ratio).toInt()),
                maxOf(1, (image.height * ratio).toInt()),
                BufferedImage.TYPE_INT_ARGB,
            )
        scaled.createGraphics().let { g ->
            try {
                g.setRenderingHint(
                    RenderingHints.KEY_INTERPOLATION,
                    RenderingHints.VALUE_INTERPOLATION_BICUBIC,
                )
                g.drawImage(image, 0, 0, scaled.width, scaled.height, null)
            } finally {
                g.dispose()
            }
        }
        if (orientation(data) != 6) return Bitmap(scaled)
        val rotated = BufferedImage(scaled.height, scaled.width, BufferedImage.TYPE_INT_ARGB)
        for (y in 0..<scaled.height) for (x in 0..<scaled.width) rotated.setRGB(
            scaled.height - 1 - y,
            x,
            scaled.getRGB(x, y),
        )
        return Bitmap(rotated)
    }

    override fun encodeSquareJPEG(
        image: TopicImageCodec.Image,
        crop: TopicImageCodec.Crop,
        edge: Int,
        quality: Double,
    ): ByteArray {
        val bitmap = (image as Bitmap).bitmap
        val output = BufferedImage(edge, edge, BufferedImage.TYPE_INT_RGB)
        output.createGraphics().let { g ->
            try {
                g.color = Color.WHITE
                g.fillRect(0, 0, edge, edge)
                g.setRenderingHint(
                    RenderingHints.KEY_INTERPOLATION,
                    RenderingHints.VALUE_INTERPOLATION_BICUBIC,
                )
                g.drawImage(
                    bitmap,
                    0,
                    0,
                    edge,
                    edge,
                    crop.x,
                    crop.y,
                    crop.x + crop.side,
                    crop.y + crop.side,
                    null,
                )
            } finally {
                g.dispose()
            }
        }
        val bytes = ByteArrayOutputStream()
        val writer = ImageIO.getImageWritersByFormatName("jpeg").next()
        try {
            ImageIO.createImageOutputStream(bytes).use { stream ->
                writer.output = stream
                val options = writer.defaultWriteParam
                options.compressionMode = ImageWriteParam.MODE_EXPLICIT
                options.compressionQuality = quality.toFloat()
                writer.write(null, IIOImage(output, null, null), options)
            }
        } finally {
            writer.dispose()
        }
        return bytes.toByteArray()
    }

    private fun orientation(data: ByteArray): Int {
        var offset = 2
        while (offset + 4 <= data.size && data[offset] == 0xff.toByte()) {
            val marker = data[offset + 1].toInt() and 255
            if (marker == 0xda || marker == 0xd9) break
            val length =
                ((data[offset + 2].toInt() and 255) shl 8) or (data[offset + 3].toInt() and 255)
            if (length < 2 || offset + 2 + length > data.size) break
            if (
                marker == 0xe1 &&
                    length >= 34 &&
                    String(data, offset + 4, 6, Charsets.ISO_8859_1) == "Exif\u0000\u0000"
            ) {
                val tiff = offset + 10
                val b =
                    ByteBuffer.wrap(data)
                        .order(
                            if (data[tiff] == 'I'.code.toByte()) ByteOrder.LITTLE_ENDIAN
                            else ByteOrder.BIG_ENDIAN,
                        )
                val ifd = tiff + b.getInt(tiff + 4)
                if (ifd + 2 <= data.size)
                    for (i in 0..<(b.getShort(ifd).toInt() and 65535)) {
                        val tag = ifd + 2 + i * 12
                        if (tag + 12 > data.size) break
                        if ((b.getShort(tag).toInt() and 65535) == 0x112)
                            return b.getShort(tag + 8).toInt()
                    }
            }
            offset += length + 2
        }
        return 1
    }
}
