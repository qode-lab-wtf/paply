package com.paply.thoughts

import com.paply.thoughts.display.*
import java.awt.Color
import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.imageio.ImageIO
import org.junit.Assert.*
import org.junit.Test

class TopicImageFileTests {
    private fun image(
        width: Int,
        height: Int,
        type: String = "jpeg",
        orientation: Int? = null,
        gps: Boolean = false,
        transparent: Boolean = false,
    ): ByteArray {
        val b =
            BufferedImage(
                width,
                height,
                if (type == "png") BufferedImage.TYPE_INT_ARGB else BufferedImage.TYPE_INT_RGB,
            )
        if (!transparent)
            b.createGraphics().let { g ->
                try {
                    g.color = Color.RED
                    g.fillRect(0, 0, width / 2, height)
                    g.color = Color.BLUE
                    g.fillRect(width / 2, 0, width - width / 2, height)
                } finally {
                    g.dispose()
                }
            }
        val out = ByteArrayOutputStream()
        check(ImageIO.write(b, type, out))
        var bytes = out.toByteArray()
        fun segment(marker: Int, payload: ByteArray): ByteArray =
            byteArrayOf(
                0xff.toByte(),
                marker.toByte(),
                ((payload.size + 2) shr 8).toByte(),
                (payload.size + 2).toByte(),
            ) + payload
        if (orientation != null) {
            val tiff =
                ByteBuffer.allocate(26)
                    .order(ByteOrder.LITTLE_ENDIAN)
                    .put('I'.code.toByte())
                    .put('I'.code.toByte())
                    .putShort(42)
                    .putInt(8)
                    .putShort(1)
                    .putShort(0x112)
                    .putShort(3)
                    .putInt(1)
                    .putShort(orientation.toShort())
                    .putShort(0)
                    .putInt(0)
                    .array()
            bytes =
                bytes.take(2).toByteArray() +
                    segment(0xe1, "Exif\u0000\u0000".toByteArray() + tiff) +
                    bytes.drop(2).toByteArray()
        }
        if (gps)
            bytes =
                bytes.take(2).toByteArray() +
                    segment(
                        0xed,
                        "GPSLatitude=52.52;GPSLongitude=13.40;TIFFMake=Testkamera".toByteArray(),
                    ) +
                    bytes.drop(2).toByteArray()
        return bytes
    }

    private fun square(bytes: ByteArray) = TopicImageFile.squareJPEG(bytes, JvmTopicImageCodec)

    private fun decode(bytes: ByteArray) = requireNotNull(ImageIO.read(ByteArrayInputStream(bytes)))

    private fun red(rgb: Int) = Color(rgb).let { it.red > 200 && it.green < 60 && it.blue < 60 }

    private fun blue(rgb: Int) = Color(rgb).let { it.red < 60 && it.green < 60 && it.blue > 200 }

    @Test
    fun largePhotoBecomesSquare512() {
        val out = requireNotNull(square(image(2000, 1500)))
        val d = decode(out)
        assertEquals(512, d.width)
        assertEquals(512, d.height)
        assertTrue(red(d.getRGB(100, 256)))
        assertTrue(blue(d.getRGB(412, 256)))
        assertTrue(out.size < 120000)
    }

    @Test
    fun smallPhotoIsNeverEnlarged() {
        val d = decode(requireNotNull(square(image(300, 200, "png"))))
        assertEquals(200, d.width)
        assertEquals(200, d.height)
    }

    @Test
    fun orientationIsApplied() {
        val d = decode(requireNotNull(square(image(400, 200, orientation = 6))))
        assertEquals(200, d.width)
        assertEquals(200, d.height)
        assertTrue(red(d.getRGB(100, 30)))
        assertTrue(blue(d.getRGB(100, 170)))
    }

    @Test
    fun metadataIsDropped() {
        val input = image(800, 600, orientation = 1, gps = true)
        assertTrue(input.toString(Charsets.ISO_8859_1).contains("Testkamera"))
        val out = requireNotNull(square(input))
        val text = out.toString(Charsets.ISO_8859_1)
        assertFalse(text.contains("Exif"))
        assertFalse(text.contains("GPS"))
        assertFalse(text.contains("Testkamera"))
        assertEquals(512, decode(out).width)
    }

    @Test
    fun transparencyBecomesWhite() {
        val d = decode(requireNotNull(square(image(64, 64, "png", transparent = true))))
        val c = Color(d.getRGB(32, 32))
        assertTrue(c.red > 235 && c.green > 235 && c.blue > 235)
    }

    @Test
    fun garbageIsRejected() {
        assertNull(square("kein Bild".toByteArray()))
        assertNull(square(byteArrayOf()))
    }

    @Test
    fun onlySimpleIDsBecomeFileNames() {
        assertEquals("t_0123abcd.jpg", TopicImageFile.fileName("t_0123abcd"))
        for (id in listOf("../topics", ".parked-x", "a/b", "")) assertNull(
            TopicImageFile.fileName(id),
        )
        assertEquals(".parked-t_1.jpg", TopicImageFile.parkedFileName("t_1"))
    }

    @Test
    fun scanSeparatesImagesParkedAndLeftovers() {
        val scan =
            TopicImageFile.scan(
                listOf(
                    "t_a.jpg",
                    ".parked-t_b.jpg",
                    "t_c.jpg.tmp",
                    ".tmp-1-t_d.jpg",
                    "notes.txt",
                    ".parked-../x.jpg",
                ),
            )
        assertEquals(setOf("t_a"), scan.images)
        assertEquals(setOf("t_b"), scan.parked)
    }

    private fun topic(id: String, mergedInto: String? = null) =
        Topic(id, id, TopicIcon.sparkles, Owner.user, mergedInto = mergedInto)

    @Test
    fun sessionPlanNeverDeletes() {
        for (topics in
            listOf(
                emptyList(),
                listOf(topic("t_b")),
                listOf(topic("t_a", "t_b"), topic("t_b")),
            )) for (saved in listOf(false, true)) {
            val plan =
                TopicImageFile.plan(
                    setOf("t_a", "t_gone"),
                    setOf("t_x"),
                    mapOf("t_b" to "t_a"),
                    topics,
                    saved,
                )
            assertTrue(plan.delete.isEmpty() && plan.dropParked.isEmpty())
        }
    }

    @Test
    fun emptyListBeforeUnlockChangesNothing() {
        assertTrue(
            TopicImageFile.plan(setOf("t_saved", "t_other"), topics = emptyList(), saved = true)
                .isEmpty,
        )
        assertTrue(
            TopicImageFile.reconcile(
                    setOf("t_saved"),
                    setOf("t_p"),
                    topics = emptyList(),
                    complete = false,
                )
                .isEmpty,
        )
        assertTrue(
            TopicImageFile.reconcile(
                    setOf("t_saved"),
                    emptySet(),
                    topics = listOf(topic("t_saved")),
                    complete = true,
                )
                .isEmpty,
        )
    }

    @Test
    fun deletedTopicKeepsItsFileUntilTheEvent() {
        assertTrue(
            TopicImageFile.plan(setOf("t_a", "t_b"), topics = listOf(topic("t_b")), saved = false)
                .isEmpty,
        )
    }

    @Test
    fun mergeIntoTopicWithImageParksTheSource() {
        val merged = listOf(topic("t_a", "t_b"), topic("t_b"))
        val plan = TopicImageFile.plan(setOf("t_a", "t_b"), topics = merged, saved = false)
        assertEquals(setOf("t_a"), plan.park)
        assertTrue(plan.adopt.isEmpty())
        assertEquals(
            setOf("t_a"),
            TopicImageFile.plan(
                    setOf("t_b"),
                    setOf("t_a"),
                    topics = listOf(topic("t_a"), topic("t_b")),
                    saved = false,
                )
                .restore,
        )
        assertTrue(
            TopicImageFile.plan(setOf("t_b"), setOf("t_a"), topics = merged, saved = true).isEmpty,
        )
    }

    @Test
    fun mergeIntoTopicWithoutImageMovesTheImage() {
        val merged = listOf(topic("t_a", "t_b"), topic("t_b"))
        assertTrue(TopicImageFile.plan(setOf("t_a"), topics = merged, saved = false).isEmpty)
        val saved = TopicImageFile.plan(setOf("t_a"), topics = merged, saved = true)
        assertEquals(mapOf("t_b" to "t_a"), saved.adopt)
        assertTrue(saved.park.isEmpty() && saved.delete.isEmpty())
        assertTrue(
            TopicImageFile.plan(
                    setOf("t_b"),
                    adopted = mapOf("t_b" to "t_a"),
                    topics = merged,
                    saved = true,
                )
                .isEmpty,
        )
        val back =
            TopicImageFile.plan(
                setOf("t_b"),
                adopted = mapOf("t_b" to "t_a"),
                topics = listOf(topic("t_a"), topic("t_b")),
                saved = false,
            )
        assertEquals(mapOf("t_b" to "t_a"), back.giveBack)
        assertTrue(back.delete.isEmpty() && back.park.isEmpty() && back.restore.isEmpty())
        assertTrue(
            TopicImageFile.plan(
                    setOf("t_b"),
                    adopted = mapOf("t_b" to "t_a"),
                    topics = listOf(topic("t_b")),
                    saved = true,
                )
                .isEmpty,
        )
    }

    @Test
    fun adoptionPicksOneSourceAndFollowsAliasChains() {
        val topics =
            listOf(topic("t_a", "t_b"), topic("t_x", "t_c"), topic("t_b", "t_c"), topic("t_c"))
        val plan = TopicImageFile.plan(setOf("t_a", "t_x"), topics = topics, saved = true)
        assertEquals(mapOf("t_c" to "t_a"), plan.adopt)
        assertEquals(setOf("t_x"), plan.park)
        val own = TopicImageFile.plan(setOf("t_a", "t_c"), topics = topics, saved = true)
        assertTrue(own.adopt.isEmpty())
        assertEquals(setOf("t_a"), own.park)
    }

    @Test
    fun reconcileNeedsACompleteList() {
        for (topics in listOf(emptyList(), listOf(topic("t_c")))) assertTrue(
            TopicImageFile.reconcile(setOf("t_a"), setOf("t_b"), topics = topics, complete = false)
                .isEmpty,
        )
    }

    @Test
    fun reconcileRetiresOrphans() {
        val plan =
            TopicImageFile.reconcile(
                setOf("t_live", "t_gone", "t_new"),
                setOf("t_old"),
                setOf("t_new"),
                listOf(topic("t_live")),
                true,
            )
        assertEquals(setOf("t_gone"), plan.delete)
        assertEquals(setOf("t_old"), plan.dropParked)
        val empty =
            TopicImageFile.reconcile(
                setOf("t_a"),
                setOf("t_b"),
                topics = emptyList(),
                complete = true,
            )
        assertEquals(setOf("t_a"), empty.delete)
        assertEquals(setOf("t_b"), empty.dropParked)
    }

    @Test
    fun reconcileParkedFromEarlierSessions() {
        val topics = listOf(topic("t_a"), topic("t_b", "t_a"), topic("t_c"))
        val plan =
            TopicImageFile.reconcile(
                setOf("t_c"),
                setOf("t_a", "t_b", "t_c", "t_gone"),
                topics = topics,
                complete = true,
            )
        assertEquals(setOf("t_a"), plan.restore)
        assertEquals(setOf("t_b", "t_c", "t_gone"), plan.dropParked)
    }

    private data class Folder(var images: Set<String>, var parked: Set<String> = emptySet()) {
        fun apply(plan: TopicImageFile.Plan) {
            for ((target, source) in plan.giveBack) if (target in images)
                images = images - target + source
            for (id in plan.restore) if (id in parked) {
                parked = parked - id
                images = images + id
            }
            for ((target, source) in plan.adopt) if (source in images)
                images = images - source + target
            for (id in plan.park) if (id in images) {
                images = images - id
                parked = parked + id
            }
            images = images - plan.delete
            parked = parked - plan.delete - plan.dropParked
        }

        fun restarted(topics: List<Topic>) =
            copy().also {
                it.apply(TopicImageFile.reconcile(images, parked, topics = topics, complete = true))
            }

        val copies
            get() = images.size + parked.size
    }

    @Test
    fun mergeAndUndoNeverLoseTheImage() {
        val apart = listOf(topic("t_a"), topic("t_b"))
        val merged = listOf(topic("t_a", "t_b"), topic("t_b"))
        val folder = Folder(setOf("t_a"))
        assertEquals(Folder(setOf("t_b")), folder.restarted(merged))
        val adopt = TopicImageFile.plan(folder.images, topics = merged, saved = true)
        folder.apply(adopt)
        assertEquals(Folder(setOf("t_b")), folder)
        assertEquals(Folder(setOf("t_b")), folder.restarted(merged))
        val back =
            TopicImageFile.plan(folder.images, adopted = adopt.adopt, topics = apart, saved = false)
        assertEquals(mapOf("t_b" to "t_a"), back.giveBack)
        val undone = folder.copy().also { it.apply(back) }
        assertEquals(Folder(setOf("t_a")), undone)
        assertEquals(Folder(setOf("t_b")), undone.restarted(merged))
        assertEquals(1, folder.restarted(apart).copies)
        assertEquals(Folder(setOf("t_a")), undone.restarted(apart))
    }

    @Test
    fun mergeIntoImageKeepsTheSourceUntilSaved() {
        val apart = listOf(topic("t_a"), topic("t_b"))
        val merged = listOf(topic("t_a", "t_b"), topic("t_b"))
        val folder = Folder(setOf("t_a", "t_b"))
        folder.apply(TopicImageFile.plan(folder.images, topics = merged, saved = false))
        assertEquals(Folder(setOf("t_b"), setOf("t_a")), folder)
        assertEquals(Folder(setOf("t_a", "t_b")), folder.restarted(apart))
        assertEquals(Folder(setOf("t_b")), folder.restarted(merged))
        assertEquals(Folder(setOf("t_b")), Folder(setOf("t_a", "t_b")).restarted(merged))
        folder.apply(
            TopicImageFile.plan(folder.images, folder.parked, topics = apart, saved = false),
        )
        assertEquals(Folder(setOf("t_a", "t_b")), folder)
    }

    @Test
    fun deletionAbortsKeepWhatIsStillNeeded() {
        val folder = Folder(setOf("t_a", "t_b"))
        assertEquals(folder, folder.restarted(listOf(topic("t_a"), topic("t_b"))))
        assertEquals(Folder(setOf("t_b")), folder.restarted(listOf(topic("t_b"))))
    }

    @Test
    fun aliasesResolveToTheirTarget() {
        val aliases =
            mapOf("t_a" to "t_b", "t_b" to "t_c", "t_loop1" to "t_loop2", "t_loop2" to "t_loop1")
        assertEquals("t_c", TopicImageFile.resolve("t_a", aliases))
        assertEquals("t_c", TopicImageFile.resolve("t_c", aliases))
        assertTrue(TopicImageFile.resolve("t_loop1", aliases) in setOf("t_loop1", "t_loop2"))
    }
}
