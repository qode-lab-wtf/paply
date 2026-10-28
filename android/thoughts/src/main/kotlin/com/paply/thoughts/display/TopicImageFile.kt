package com.paply.thoughts.display

import com.paply.thoughts.Topic
import kotlin.math.ceil

/**
 * Platform codec: apply EXIF orientation when decoding; encode sRGB JPEG from fresh pixels,
 * compositing transparency on white and copying NO source metadata (GPS, EXIF, camera, comments).
 * No file/network access is needed. Image is an opaque platform bitmap handle.
 */
interface TopicImageCodec {
    data class Dimensions(val width: Int, val height: Int)

    interface Image {
        val width: Int
        val height: Int
    }

    data class Crop(val x: Int, val y: Int, val side: Int)

    fun dimensions(data: ByteArray): Dimensions?

    fun orientedThumbnail(data: ByteArray, maxDimension: Int): Image?

    fun encodeSquareJPEG(image: Image, crop: Crop, edge: Int, quality: Double): ByteArray?
}

object TopicImageFile {
    const val directoryName = "topic-images"
    const val maxPixel = 512
    const val jpegQuality = 0.8
    internal const val parkedPrefix = ".parked-"
    internal const val suffix = ".jpg"

    fun isValidID(id: String) =
        id.toByteArray(Charsets.UTF_8).size in 1..80 &&
            id.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '_' || it == '-' }

    fun fileName(topicID: String) = if (isValidID(topicID)) topicID + suffix else null

    fun parkedFileName(topicID: String) =
        if (isValidID(topicID)) parkedPrefix + topicID + suffix else null

    data class Scan(val images: Set<String>, val parked: Set<String>)

    fun scan(names: List<String>): Scan {
        val images = mutableSetOf<String>()
        val parked = mutableSetOf<String>()
        for (name in names.filter { it.endsWith(suffix) }) {
            val stem = name.removeSuffix(suffix)
            if (stem.startsWith(parkedPrefix))
                stem.removePrefix(parkedPrefix).takeIf(::isValidID)?.let(parked::add)
            else stem.takeIf(::isValidID)?.let(images::add)
        }
        return Scan(images, parked)
    }

    data class Plan(
        val adopt: Map<String, String> = emptyMap(),
        val giveBack: Map<String, String> = emptyMap(),
        val park: Set<String> = emptySet(),
        val restore: Set<String> = emptySet(),
        val delete: Set<String> = emptySet(),
        val dropParked: Set<String> = emptySet(),
    ) {
        val isEmpty
            get() = this == Plan()
    }

    fun plan(
        images: Set<String>,
        parked: Set<String> = emptySet(),
        adopted: Map<String, String> = emptyMap(),
        topics: List<Topic>,
        saved: Boolean,
    ): Plan {
        val byID = topics.distinctBy { it.id }.associateBy { it.id }
        fun standalone(id: String) = byID[id]?.let { it.mergedInto == null } == true
        val back = adopted.filter { (target, source) ->
            standalone(source) && standalone(target) && target in images && source !in images
        }
        val returning = back.values.toSet()
        val restore = parked.filter { standalone(it) && it !in images && it !in returning }.toSet()
        return mergedImages(images, topics, byID, Plan(giveBack = back, restore = restore)) {
            _,
            free ->
            if (free) {
                if (saved) MergedImage.adopt else MergedImage.wait
            } else MergedImage.park
        }
    }

    fun reconcile(
        images: Set<String>,
        parked: Set<String>,
        keep: Set<String> = emptySet(),
        topics: List<Topic>,
        complete: Boolean,
    ): Plan {
        if (!complete) return Plan()
        val byID = topics.distinctBy { it.id }.associateBy { it.id }
        val restore = mutableSetOf<String>()
        val drop = mutableSetOf<String>()
        for (id in parked - keep) if (
            byID[id]?.let { it.mergedInto == null } == true && id !in images
        )
            restore.add(id)
        else drop.add(id)
        val delete = images.filter { it !in byID && it !in keep }.toSet()
        return mergedImages(
            images,
            topics,
            byID,
            Plan(restore = restore, delete = delete, dropParked = drop),
        ) { id, free ->
            if (id in keep) MergedImage.wait
            else if (free) MergedImage.adopt else MergedImage.delete
        }
    }

    private enum class MergedImage {
        adopt,
        park,
        delete,
        wait,
    }

    private fun mergedImages(
        images: Set<String>,
        topics: List<Topic>,
        byID: Map<String, Topic>,
        initial: Plan,
        decide: (String, Boolean) -> MergedImage,
    ): Plan {
        val aliases = topics.filter { it.mergedInto != null }.associate { it.id to it.mergedInto!! }
        var plan = initial
        for (topic in topics.filter { it.mergedInto != null && it.id in images }) {
            val target = resolve(topic.id, aliases)
            val free =
                target != topic.id &&
                    isValidID(target) &&
                    byID[target]?.let { it.mergedInto == null } == true &&
                    target !in images &&
                    target !in plan.restore &&
                    target !in plan.giveBack &&
                    target !in plan.adopt
            plan =
                when (decide(topic.id, free)) {
                    MergedImage.adopt -> plan.copy(adopt = plan.adopt + (target to topic.id))
                    MergedImage.park -> plan.copy(park = plan.park + topic.id)
                    MergedImage.delete -> plan.copy(delete = plan.delete + topic.id)
                    MergedImage.wait -> plan
                }
        }
        return plan
    }

    fun resolve(id: String, aliases: Map<String, String>): String {
        var current = id
        val seen = mutableSetOf(id)
        while (true) {
            val next = aliases[current] ?: break
            if (!seen.add(next)) break
            current = next
        }
        return current
    }

    fun squareJPEG(
        data: ByteArray,
        codec: TopicImageCodec,
        maxPixel: Int = this.maxPixel,
        quality: Double = jpegQuality,
    ): ByteArray? {
        if (maxPixel <= 0) return null
        val size = codec.dimensions(data) ?: return null
        if (size.width <= 0 || size.height <= 0) return null
        val short = minOf(size.width, size.height).toDouble()
        val long = maxOf(size.width, size.height).toDouble()
        val target = minOf(short, maxPixel.toDouble())
        val thumbnailSize = ceil(long * target / short).coerceIn(1.0, 8192.0).toInt()
        val image = codec.orientedThumbnail(data, thumbnailSize) ?: return null
        val side = minOf(image.width, image.height)
        if (side <= 0) return null
        return codec.encodeSquareJPEG(
            image,
            TopicImageCodec.Crop((image.width - side) / 2, (image.height - side) / 2, side),
            minOf(side, maxPixel),
            quality,
        )
    }
}
