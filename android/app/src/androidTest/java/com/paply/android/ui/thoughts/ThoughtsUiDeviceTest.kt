package com.paply.android.ui.thoughts

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.platform.app.InstrumentationRegistry
import com.paply.android.BuildConfig
import com.paply.android.MainActivity
import com.paply.android.settings.KeyVault
import com.paply.android.thoughts.AndroidTopicImageCodec
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.thoughts.*
import com.paply.thoughts.display.TopicImageFile
import com.paply.thoughts.model.TopicSuggestion
import com.paply.thoughts.processing.PartSplitter
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.Instant
import java.time.ZoneId

/** Debug-only offline fixture and UI acceptance. No production fixture endpoint or Groq client. */
class ThoughtsUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val repository get() = ThoughtsRepository.get(context)

    @Test fun seedExamples() = runBlocking {
        check(BuildConfig.DEBUG)
        check(KeyVault(context).read() == null) { "UI fixtures require an emulator without a Groq key" }
        val store = repository.backend().store
        repository.workMutex.lock()
        try {
            store.purge(store.all().filter { it.id.startsWith("s_ui_") }.map { it.id })
            val now = Instant.now()
            val garden = Topic(id="t_ui_garden", title="Garten", icon=TopicIcon.leaf, owner=Owner.ai, createdAt=now.minusSeconds(80000))
            val paply = Topic(id="t_ui_paply", title="Paply", icon=TopicIcon.code, owner=Owner.user, note="Meine App für freie Gedanken", createdAt=now.minusSeconds(70000))
            val move = Topic(id="t_ui_move", title="Balkon", icon=TopicIcon.home, owner=Owner.ai, createdAt=now.minusSeconds(60000))
            val travel = Topic(id="t_ui_trip", title="Lissabon", icon=TopicIcon.plane, owner=Owner.ai, createdAt=now.minusSeconds(50000))
            store.updateTopics { it.filterNot { topic -> topic.id.startsWith("t_ui_") } + listOf(garden,paply,move,travel) }
            val today = now.atZone(ZoneId.systemDefault()).toLocalDate().atStartOfDay(ZoneId.systemDefault()).toInstant()
            fun save(id: String, title: String, text: String, topic: Topic?, at: Instant, tasks: List<ThoughtTask> = emptyList(), links: List<ThoughtLink> = emptyList(), deleted: Boolean = false) {
                val thought = Thought(id=id, trigger=ThoughtTrigger.app, state=ThoughtState.done, title=title, titleOwner=Owner.ai,
                    text=text, textOwner=Owner.ai, durationMs=72000, topicId=topic?.id, topicOwner=Owner.ai, createdAt=at,
                    tasks=tasks, links=links, languages=listOf("de"), deletedAt=if (deleted) now.minusSeconds(86400) else null)
                store.save(thought)
                val raw = "Ähm, also, $text"
                store.saveSourceOnce(id, ThoughtSource(raw, PartSplitter.sentences(raw,id),"offline-ui-fixture", at,listOf("de"),72.0))
            }
            save("s_ui_garden_older", "Den Balkon grüner machen", "Die Tomaten können an der sonnigen Wand stehen. Die Kräuter bleiben am Fenster.", garden, now.minusSeconds(86400),
                tasks=listOf(ThoughtTask(id="k_ui_done",text="Kräuter ans Fenster stellen",done=true,doneAt=now.minusSeconds(3600),owner=Owner.ai)))
            save("s_ui_garden", "Tomaten brauchen größere Töpfe", "Die Tomaten brauchen größere Töpfe. Ich besorge morgen neue Töpfe und frische Erde.\n\nDie alten Töpfe können wir für die Kräuter nehmen.",garden,now.minusSeconds(600),
                tasks=listOf(ThoughtTask(id="k_ui_pots",text="Töpfe besorgen",quote="Ich besorge morgen neue Töpfe",dueHint="morgen",dueAt=today.plusSeconds(86400+14*3600),dueHasTime=false,owner=Owner.ai),
                    ThoughtTask(id="k_ui_water",text="Tomaten gießen",quote="Ich muss die Tomaten gießen",dueAt=today.plusSeconds(12*3600),owner=Owner.ai)),
                links=listOf(ThoughtLink("s_ui_garden_older",LinkKind.continues,"Die Tomaten auf dem Balkon",Owner.ai)))
            save("s_ui_paply", "Gedanken unterwegs festhalten", "Ein Druck auf die Paply-Kachel genügt. Ich muss die neue Anleitung testen. Das Widget soll direkt auf den Home-Bildschirm.",paply,now.minusSeconds(3600),
                tasks=listOf(ThoughtTask(id="k_ui_guide",text="Neue Anleitung testen",dueHint="gestern",dueAt=today.minusSeconds(86400),owner=Owner.ai)))
            save("s_ui_paply_older", "Ein ruhiger Platz für Ideen", "Gedanken sollen leicht wiederzufinden sein. Titel, Themen und Verbindungen helfen dabei.",paply,now.minusSeconds(3*86400),
                tasks=listOf(ThoughtTask(id="k_ui_someday",text="Freunde nach Feedback fragen",owner=Owner.user)))
            save("s_ui_balcony", "Eine Bank für den Balkon", "Vielleicht passt eine kleine Bank neben die Tür. Erst ausmessen, bevor wir etwas kaufen.",move,now.minusSeconds(5*86400))
            save("s_ui_none", "Eine Idee beim Spaziergang", "Mehr Zeit ohne Bildschirm tut gut. Diesen Gedanken will ich einfach festhalten.",null,now.minusSeconds(7*86400))
            save("s_ui_deleted", "Mit dem Zug nach Lissabon", "Wir könnten im Frühjahr mit dem Zug nach Lissabon fahren.",travel,now.minusSeconds(10*86400),deleted=true)
            store.save(Thought(id="s_ui_waiting",trigger=ThoughtTrigger.app,state=ThoughtState.waitingKey,createdAt=now.minusSeconds(60),durationMs=19000,
                status=Thought.Status("Gesichert · Groq-Schlüssel fehlt"),audio=Thought.AudioInfo("audio.wav")))
            store.save(Thought(id="s_ui_error",trigger=ThoughtTrigger.app,state=ThoughtState.needsAttention,createdAt=now.minusSeconds(120),durationMs=42000,
                status=Thought.Status("Ton gesichert · nicht verschriftlicht"),audio=Thought.AudioInfo("audio.wav")))
            store.setPendingSuggestions(listOf(TopicSuggestion(garden.id,move.id,"Garten","Beide Themen betreffen den Garten und den Balkon.")))
            repository.publish(store)
        } finally { repository.workMutex.unlock() }
    }

    @Test fun topicEditingMergeUndoLinksAndTasksPreserveOriginal() = runBlocking {
        val store = repository.backend().store
        val prefix = "testui_" + System.nanoTime()
        val a = repository.createTopic("Test Garten", TopicIcon.leaf)
        val b = repository.createTopic("Test Balkon", TopicIcon.home)
        val id = prefix + "a"; val other = prefix + "b"
        try {
            store.save(Thought(id=id,trigger=ThoughtTrigger.app,state=ThoughtState.done,title="Titel",text="Originaler Text",topicId=a.id))
            store.save(Thought(id=other,trigger=ThoughtTrigger.app,state=ThoughtState.done,title="Anderer",text="Anderer Gedanke",createdAt=Instant.now().plusSeconds(1),topicId=b.id))
            val source = ThoughtSource("Ähm, originaler Text",emptyList(),"fixture",Instant.now(),listOf("de"),1.0)
            store.saveSourceOnce(id,source)
            repository.updateTopic(a.id,"Umbenannt",TopicIcon.sun,"Meine Tomaten")
            assertEquals(Owner.user,store.resolveTopic(a.id)?.owner)
            repository.edit(id,"Mein Titel","Mein Text")
            repository.addTask(id,"Neue Aufgabe")
            val task = store.thought(id)!!.tasks.single()
            repository.editTask(id,task.id,"Eigene Aufgabe")
            assertEquals(Owner.user,store.thought(id)!!.tasks.single().owner)
            repository.setTaskDone(id,task.id,true)
            val undoTask = repository.deleteTask(id,task.id)
            assertTrue(store.thought(id)!!.tasks.isEmpty())
            undoTask()
            assertTrue(store.thought(id)!!.tasks.single().done)
            repository.addLink(id,other)
            assertTrue(store.thought(id)!!.links.isEmpty())
            assertEquals(id,store.thought(other)!!.links.single().target)
            repository.removeLink(id,other)
            assertTrue(store.thought(other)!!.links.isEmpty())
            val undo = repository.mergeTopics(listOf(a.id,b.id),b.id)
            assertEquals(b.id,store.thought(id)!!.topicId)
            assertEquals(b.id,store.resolveTopic(a.id)?.id)
            undo()
            assertEquals(a.id,store.thought(id)!!.topicId)
            assertEquals(a.id,store.resolveTopic(a.id)?.id)
            assertEquals(source,repository.source(id))
            assertEquals(Owner.user,store.thought(id)!!.textOwner)
        } finally { store.purge(listOf(id,other)); repository.deleteTopic(a.id); repository.deleteTopic(b.id) }
    }

    @Test fun topicPictureAndColorReturnWithMergeUndo() = runBlocking {
        val a = repository.createTopic("Bildquelle",TopicIcon.camera)
        val b = repository.createTopic("Bildziel",TopicIcon.home)
        try {
            val bitmap = Bitmap.createBitmap(80,60,Bitmap.Config.ARGB_8888).apply { eraseColor(Color.RED) }
            val bytes = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }.toByteArray()
            bitmap.recycle()
            repository.setTopicImage(a.id, bytes)
            val image = repository.topicImages().getValue(a.id)
            val slot = repository.topicColorSlots().getValue(a.id)
            val undo = repository.mergeTopics(listOf(a.id),b.id)
            assertArrayEquals(image,repository.topicImages()[b.id])
            repository.topicColorSlots() // Render the merged state before undo, as the real UI does.
            undo()
            assertArrayEquals(image,repository.topicImages()[a.id])
            assertNull(repository.topicImages()[b.id])
            assertEquals(slot,repository.topicColorSlots()[a.id])
        } finally { repository.deleteTopic(a.id); repository.deleteTopic(b.id) }
    }

    @Test fun trashRestoresAndFinalDeletionCarriesTopic() = runBlocking {
        val store = repository.backend().store
        val topic = repository.createTopic("Nur für den Papierkorb",TopicIcon.book)
        val id = "testui_trash_" + System.nanoTime()
        store.save(Thought(id=id,trigger=ThoughtTrigger.app,state=ThoughtState.done,title="Wiederherstellbar",topicId=topic.id))
        repository.trash(id)
        assertNotNull(store.thought(id)?.deletedAt)
        assertNotNull(store.resolveTopic(topic.id))
        repository.restore(id)
        assertNull(store.thought(id)?.deletedAt)
        repository.trash(id)
        repository.permanentlyDelete(id)
        assertNull(store.thought(id))
        assertNull(store.resolveTopic(topic.id))
    }

    @Test fun androidCodecCropsFlattensAndStripsMetadata() {
        val bitmap = Bitmap.createBitmap(1200,800,Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.TRANSPARENT)
        val bytes = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }.toByteArray()
        bitmap.recycle()
        val jpeg = TopicImageFile.squareJPEG(bytes,AndroidTopicImageCodec())!!
        val decoded = BitmapFactory.decodeByteArray(jpeg,0,jpeg.size)
        assertEquals(512,decoded.width); assertEquals(512,decoded.height)
        assertTrue(Color.red(decoded.getPixel(20,20)) > 245)
        assertFalse(String(jpeg,Charsets.ISO_8859_1).contains("Exif"))
        decoded.recycle()
        val small = Bitmap.createBitmap(40,60,Bitmap.Config.ARGB_8888)
        val smallBytes = ByteArrayOutputStream().also { small.compress(Bitmap.CompressFormat.PNG,100,it) }.toByteArray()
        small.recycle()
        val smallJpeg = TopicImageFile.squareJPEG(smallBytes,AndroidTopicImageCodec())!!
        val smallDecoded = BitmapFactory.decodeByteArray(smallJpeg,0,smallJpeg.size)
        assertEquals(40,smallDecoded.width); assertEquals(40,smallDecoded.height)
        smallDecoded.recycle()
    }

    @Test fun androidCodecAppliesExifBeforeSquareCrop() {
        val original = Bitmap.createBitmap(80,40,Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(original)
        canvas.drawColor(Color.BLUE)
        canvas.drawRect(0f,0f,40f,40f,android.graphics.Paint().apply { color = Color.RED })
        val plain = ByteArrayOutputStream().also { original.compress(Bitmap.CompressFormat.JPEG,100,it) }.toByteArray()
        original.recycle()
        // A little-endian TIFF IFD with orientation 6 (90° clockwise); no third-party EXIF library.
        val exif = byteArrayOf(69,120,105,102,0,0,73,73,42,0,8,0,0,0,1,0,18,1,3,0,1,0,0,0,6,0,0,0,0,0,0,0)
        val withExif = plain.take(2).toByteArray() + byteArrayOf(0xff.toByte(),0xe1.toByte(),0,(exif.size+2).toByte()) + exif + plain.drop(2).toByteArray()
        val clean = requireNotNull(TopicImageFile.squareJPEG(withExif,AndroidTopicImageCodec()))
        val decoded = BitmapFactory.decodeByteArray(clean,0,clean.size)
        assertEquals(40,decoded.width); assertEquals(40,decoded.height)
        assertTrue(Color.red(decoded.getPixel(20,5)) > 180)
        assertTrue(Color.blue(decoded.getPixel(20,35)) > 180)
        assertFalse(String(clean,Charsets.ISO_8859_1).contains("Exif"))
        decoded.recycle()
    }

    @Test fun fixtureUiOpensDetailOriginalTopicPickerAndTasks() {
        runBlocking { seedExamples() }
        context.startActivity(Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        assertVisible("Tomaten brauchen größere Töpfe")
        assertFalse(nodes().any { it.text?.toString() == "Löschen" })
        tap("Tomaten brauchen größere Töpfe")
        scrollForward()
        tap("Original ›")
        assertVisible("Ähm, also,")
        scrollBackward()
        tap("Garten")
        assertVisible("Neues Thema …")
        tap("Abbrechen")
        tapDescription("Zurück")
        tapDescriptionOrTextLast("Aufgaben")
        assertVisible("Überfällig")
        assertVisible("Heute")
        assertVisible("Neue Anleitung testen")
    }

    @Test fun hygieneSuggestionWaitsForConfirmation() {
        seedExamples()
        context.startActivity(Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        assertVisible("Tomaten brauchen größere Töpfe")
        tapDescription("Mehr"); tap("Themen bearbeiten"); tap("Zusammenführen")
        assertVisible("Themen zusammenführen?")
        assertEquals("t_ui_garden",runBlocking { repository.backend().store.resolveTopic("t_ui_garden")?.id })
        assertEquals("t_ui_move",runBlocking { repository.backend().store.resolveTopic("t_ui_move")?.id })
        tap("Abbrechen")
        assertEquals(1,repository.suggestions.value.size)
    }

    @Test fun delayedTaskCheckoffSurvivesTabChangeAndCanBeCancelled() {
        seedExamples()
        context.startActivity(Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        tap("Tomaten brauchen größere Töpfe")
        tapDescription("Abhaken: Töpfe besorgen")
        tapDescription("Erledigt: Töpfe besorgen")
        android.os.SystemClock.sleep(1400)
        assertFalse(runBlocking { repository.thought("s_ui_garden")!!.tasks.first { it.id == "k_ui_pots" }.done })
        tapDescription("Abhaken: Töpfe besorgen")
        tapDescriptionOrTextLast("Aufgaben")
        android.os.SystemClock.sleep(1400)
        assertTrue(runBlocking { repository.thought("s_ui_garden")!!.tasks.first { it.id == "k_ui_pots" }.done })
        tapDescriptionOrTextLast("Gedanken")
        tapDescription("Erledigt: Töpfe besorgen")
        assertFalse(runBlocking { repository.thought("s_ui_garden")!!.tasks.first { it.id == "k_ui_pots" }.done })
    }

    /** Invoke this method explicitly with -e appearance light|dark; saves real device PNGs. */
    @Test fun captureScreenshots() {
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("screenshots") == "true")
        seedExamples()
        val appearance = InstrumentationRegistry.getArguments().getString("appearance") ?: "light"
        fun shot(screen: String) {
            instrumentation.waitForIdleSync(); android.os.SystemClock.sleep(600)
            val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
            val directory = requireNotNull(context.getExternalFilesDir("ui-shots")).apply { mkdirs() }
            File(directory,"ui-$screen-$appearance.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }
            bitmap.recycle()
        }
        context.startActivity(Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        assertVisible("Tomaten brauchen größere Töpfe")
        shot("home")
        tap("Gedanke · 0:42"); assertVisible("Erneut versuchen"); shot("error"); tapDescription("Zurück")
        tap("Gedanke · 0:19"); assertVisible("Eintragen"); shot("waiting"); tapDescription("Zurück")
        tap("Garten"); shot("topic")
        tap("Tomaten brauchen größere Töpfe"); shot("detail")
        scrollForward(); tap("Original ›"); scrollForward(); shot("original")
        scrollBackward(); tap("Tomaten brauchen größere Töpfe"); shot("edit-thought"); tap("Fertig")
        tap("Garten"); shot("topic-picker")
        tap("Neues Thema …"); shot("topic-new"); tap("Abbrechen")
        tapDescription("Mehr"); tap("Aufgabe hinzufügen"); shot("task-new"); tap("Abbrechen")
        tapDescription("Mehr"); tap("Verknüpfen …"); shot("link-picker"); tap("Abbrechen")
        tapDescription("Zurück")
        tapDescription("Suchen"); shot("search")
        setField("Gedanken durchsuchen","Tomaten"); shot("search-results")
        setField("Tomaten","xyzkeintreffer"); shot("search-empty")
        tapDescription("Zurück")
        tapDescription("Mehr"); tap("Themen bearbeiten"); shot("topics")
        tap("Zusammenführen"); shot("suggestion-confirm"); tap("Abbrechen")
        tap("Paply"); shot("topic-edit"); scrollForward(); shot("topic-icons"); tap("Abbrechen")
        tap("Auswählen"); selectTopic("Garten"); selectTopic("Paply"); tap("2 zusammenführen"); shot("topic-merge"); tap("Abbrechen")
        tap("Fertig"); tapDescription("Zurück")
        tapDescription("Mehr"); tap("Zuletzt gelöscht (1)"); shot("deleted")
        tapDescription("Gelöschten Gedanken verwalten"); shot("deleted-actions"); tap("Endgültig löschen"); shot("purge-confirm"); tap("Abbrechen")
        tap("Alle löschen"); shot("purge-all-confirm"); tap("Abbrechen"); tapDescription("Zurück")
        tapDescriptionOrTextLast("Aufgaben"); shot("tasks")
        tapDescription("Aufgabenaktionen: Neue Anleitung testen"); tap("Bearbeiten"); shot("task-edit"); tap("Abbrechen")
        scrollForward(); tap("Erledigt ›"); scrollForward(); shot("tasks-done")
        tapDescriptionOrTextLast("Gedanken")
        // Empty states use the same fixture store, and are restored before this method exits.
        val ids = runBlocking { repository.thoughts.value.map { it.id }.also { ids -> ids.forEach { repository.trash(it) } } }
        try {
            tapDescriptionOrTextLast("Aufgaben"); shot("tasks-empty")
            tapDescriptionOrTextLast("Gedanken"); assertVisible("Deine Gedanken"); shot("empty")
            tap("Knopf einrichten"); shot("guide"); scrollForward(); shot("guide-widget")
        } finally { runBlocking { ids.forEach { repository.restore(it) } } }
    }

    @Test fun captureBarScreenshot() {
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("screenshots") == "true")
        check(BuildConfig.DEBUG)
        seedExamples()
        val previous = com.paply.android.ThoughtState.current.value
        try {
            // A UI fixture only: no microphone, service command or Groq request is started.
            com.paply.android.ThoughtState.current.value = com.paply.android.ThoughtState.State(
                phase="recording",id="s_ui_recording",elapsedMs=72000,level=.65f)
            context.startActivity(Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
            assertVisible("Gedanke · 1:12")
            android.os.SystemClock.sleep(600)
            val appearance = InstrumentationRegistry.getArguments().getString("appearance") ?: "light"
            val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
            val directory = requireNotNull(context.getExternalFilesDir("ui-shots")).apply { mkdirs() }
            File(directory,"ui-capture-bar-$appearance.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }
            bitmap.recycle()
        } finally { com.paply.android.ThoughtState.current.value = previous }
    }

    private fun selectTopic(title: String) {
        fun contains(node: AccessibilityNodeInfo): Boolean = node.text?.toString() == title ||
            (0 until node.childCount).any { index -> node.getChild(index)?.let(::contains) == true }
        fun row(node: AccessibilityNodeInfo) = node.isCheckable && contains(node)
        val node = waitNode { row(it) }
        if (!node.isChecked) click(node)
        waitNode { row(it) && it.isChecked }
    }

    private fun setField(current: String, value: String) {
        val node = waitNode { it.actionList.any { action -> action.id == AccessibilityNodeInfo.ACTION_SET_TEXT } }
        click(node)
        val refreshed = waitNode { it.actionList.any { action -> action.id == AccessibilityNodeInfo.ACTION_SET_TEXT } }
        check(refreshed.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,value)
        })) { "Focused search field refused text replacement: $current" }
        instrumentation.waitForIdleSync(); android.os.SystemClock.sleep(350)
        assertVisible(value)
    }

    private fun scrollForward() = scrollGesture(true)
    private fun scrollBackward() { repeat(3) { scrollGesture(false) } }
    private fun scrollGesture(forward: Boolean) {
        val node = nodes().firstOrNull { it.isScrollable } ?: return
        val bounds = android.graphics.Rect().also(node::getBoundsInScreen)
        val x = bounds.exactCenterX()
        val start = bounds.top + bounds.height() * if (forward) .8f else .25f
        val end = bounds.top + bounds.height() * if (forward) .25f else .8f
        val at = android.os.SystemClock.uptimeMillis()
        fun event(action: Int, y: Float) {
            val input = android.view.MotionEvent.obtain(at,android.os.SystemClock.uptimeMillis(),action,x,y,0)
            try { check(instrumentation.uiAutomation.injectInputEvent(input,true)) } finally { input.recycle() }
        }
        event(android.view.MotionEvent.ACTION_DOWN,start)
        for (step in 1..12) { android.os.SystemClock.sleep(22); event(android.view.MotionEvent.ACTION_MOVE,start+(end-start)*step/12) }
        event(android.view.MotionEvent.ACTION_UP,end)
        instrumentation.waitForIdleSync(); android.os.SystemClock.sleep(450)
    }

    private fun tapDescriptionOrTextLast(text: String) {
        waitNode { it.text?.toString() == text }
        click(nodes().last { it.text?.toString() == text })
    }
    private fun nodes(): List<AccessibilityNodeInfo> {
        if (android.os.Build.VERSION.SDK_INT >= 33) instrumentation.uiAutomation.clearCache()
        val root = instrumentation.uiAutomation.rootInActiveWindow ?: return emptyList()
        val result = mutableListOf<AccessibilityNodeInfo>()
        fun walk(node: AccessibilityNodeInfo) { result += node; for (i in 0 until node.childCount) node.getChild(i)?.let(::walk) }
        walk(root); return result
    }
    private fun waitNode(predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo {
        val until = android.os.SystemClock.uptimeMillis() + 8000
        while (android.os.SystemClock.uptimeMillis() < until) {
            nodes().firstOrNull(predicate)?.let { return it }
            android.os.SystemClock.sleep(120)
        }
        error("UI node missing. Visible: " + nodes().mapNotNull { it.text ?: it.contentDescription }.joinToString(" | "))
    }
    private fun tap(text: String) = click(waitNode { it.text?.toString() == text })
    private fun tapDescription(text: String) = click(waitNode { it.contentDescription?.toString() == text })
    private fun click(node: AccessibilityNodeInfo) {
        // Real input at observed node bounds also works when Compose replaces a semantics node mid-frame.
        val bounds = android.graphics.Rect()
        node.getBoundsInScreen(bounds)
        check(!bounds.isEmpty) { "No visible bounds for ${node.text ?: node.contentDescription}" }
        val at = android.os.SystemClock.uptimeMillis()
        val down = android.view.MotionEvent.obtain(at,at,android.view.MotionEvent.ACTION_DOWN,bounds.exactCenterX(),bounds.exactCenterY(),0)
        try {
            check(instrumentation.uiAutomation.injectInputEvent(down,true))
            android.os.SystemClock.sleep(70)
            val up = android.view.MotionEvent.obtain(at,android.os.SystemClock.uptimeMillis(),android.view.MotionEvent.ACTION_UP,bounds.exactCenterX(),bounds.exactCenterY(),0)
            try { check(instrumentation.uiAutomation.injectInputEvent(up,true)) } finally { up.recycle() }
        } finally { down.recycle() }
        instrumentation.waitForIdleSync(); android.os.SystemClock.sleep(450)
    }

    private fun assertVisible(text: String) { waitNode { it.text?.contains(text) == true || it.contentDescription?.contains(text) == true } }
}
