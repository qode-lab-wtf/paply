package com.paply.android.ui.thoughts

import android.content.Intent
import android.graphics.Rect
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.platform.app.InstrumentationRegistry
import com.paply.android.BuildConfig
import com.paply.android.MainActivity
import com.paply.android.settings.KeyVault
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.thoughts.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant
import java.io.File

/** Offline debug data and real input, including a two-pointer pinch. No Groq calls. */
class ThoughtMapDeviceTest {
    private val instrumentation get()=InstrumentationRegistry.getInstrumentation()
    private val context get()=instrumentation.targetContext
    private val repository get()=ThoughtsRepository.get(context)

    @Test fun seedMapExamples():Unit=runBlocking {
        check(BuildConfig.DEBUG && KeyVault(context).read()==null)
        ThoughtsUiDeviceTest().seedExamples()
        val store=repository.backend().store
        repository.workMutex.lock()
        try {
            store.purge(store.all().filter { it.id.startsWith("s_map_") || it.id.startsWith("s_stress_") }.map { it.id })
            val now=Instant.now()
            val titles=listOf("Lesen","Musik","Freunde","Bewegung","Kochen","Arbeit","Fotografie","Familie","Reisen","Ideen")
            val icons=listOf(TopicIcon.book,TopicIcon.music,TopicIcon.users,TopicIcon.sun,TopicIcon.coffee,TopicIcon.briefcase,TopicIcon.camera,TopicIcon.heart,TopicIcon.mapPin,TopicIcon.lightbulb)
            val added=titles.mapIndexed { i,title -> Topic("t_map_$i",title,icons[i],Owner.ai,now.minusSeconds((i+1)*86400L)) }
            store.updateTopics { it.filterNot { t -> t.id.startsWith("t_map_") || t.id.startsWith("t_stress_") } + added }
            val topics=store.topics().filter { it.mergedInto==null }
            repeat(32) { i ->
                val topic=topics[i%topics.size]
                val title=when(topic.title) {
                    "Garten"->if(i<14) "Kräuter am Küchenfenster" else "Ein Platz für die Erdbeeren"
                    "Paply"->if(i<14) "Ideen mit Freunden teilen" else "Eine Karte für meine Gedanken"
                    "Lesen"->"Das nächste Buch für den Herbst"
                    "Musik"->"Ein Konzert im November"
                    "Freunde"->"Wieder zusammen kochen"
                    "Familie"->"Am Sonntag gemeinsam frühstücken"
                    "Kochen"->"Kürbissuppe mit Ingwer"
                    "Fotografie"->"Das Licht am frühen Morgen"
                    "Arbeit"->"Mehr Raum für konzentrierte Arbeit"
                    "Bewegung"->"Eine Runde am Fluss laufen"
                    "Lissabon"->"Mit dem Nachtzug ans Meer"
                    "Balkon"->"Die kleine Bank aus Holz"
                    "Reisen"->"Ein Wochenende in den Bergen"
                    else->"Was mir beim Spazieren einfällt"
                }
                val older=if(i>=14) "s_map_${i-14}" else null
                val links=buildList {
                    if(older!=null) add(ThoughtLink(older,LinkKind.continues,"Der Gedanke geht weiter",Owner.user))
                    if(i in listOf(4,18)) add(ThoughtLink(if(i==4) "s_ui_garden" else "s_ui_garden_older",LinkKind.sameMatter,"Gemeinsamer Plan",Owner.user))
                }
                store.save(Thought(id="s_map_$i",trigger=ThoughtTrigger.app,state=ThoughtState.done,createdAt=now.minusSeconds(1800+i*7100L),
                    title=title,text="${title}. Das möchte ich mir in Ruhe ansehen und später darauf zurückkommen. Ein kleiner Schritt reicht für den Anfang.",
                    topicId=topic.id,topicOwner=Owner.ai,links=links,tasks=if(i%4==0) listOf(ThoughtTask(id="k_map_$i",text=when(topic.title) {
                        "Lesen"->"Das Buch in der Bücherei suchen"; "Familie"->"Für Sonntag verabreden"; else->"${topic.title}: nächsten Schritt planen"
                    },owner=Owner.user)) else emptyList()))
            }
            repository.publish(store)
            assertEquals(40,repository.thoughts.value.size)
            assertEquals(14,repository.topics.value.size)
        } finally { repository.workMutex.unlock() }
        // A local photo-shaped fixture also exercises the image cache; nothing is downloaded.
        val picture=android.graphics.Bitmap.createBitmap(128,128,android.graphics.Bitmap.Config.ARGB_8888)
        val canvas=android.graphics.Canvas(picture)
        val paint=android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
        paint.shader=android.graphics.LinearGradient(0f,0f,128f,128f,android.graphics.Color.rgb(129,194,207),android.graphics.Color.rgb(22,72,52),android.graphics.Shader.TileMode.CLAMP)
        canvas.drawRect(0f,0f,128f,128f,paint)
        paint.shader=null; paint.color=android.graphics.Color.rgb(255,219,122); canvas.drawCircle(91f,31f,16f,paint)
        paint.color=android.graphics.Color.rgb(40,95,70)
        canvas.drawPath(android.graphics.Path().apply { moveTo(0f,118f); lineTo(47f,54f); lineTo(101f,128f); close() },paint)
        paint.color=android.graphics.Color.rgb(18,61,43)
        canvas.drawPath(android.graphics.Path().apply { moveTo(41f,128f); lineTo(101f,71f); lineTo(128f,104f); lineTo(128f,128f); close() },paint)
        val bytes=java.io.ByteArrayOutputStream().also { picture.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }.toByteArray()
        picture.recycle(); repository.setTopicImage("t_map_6",bytes)
    }

    @Test fun seedStressExamples():Unit=runBlocking {
        seedMapExamples()
        val store=repository.backend().store
        repository.workMutex.lock()
        try {
            val now=Instant.now()
            val topics=(0 until 30).map { Topic("t_stress_$it","Thema ${it+1}",TopicIcon.entries[it%24],Owner.ai,now.minusSeconds(it*3600L)) }
            store.purge(store.all().map { it.id })
            store.updateTopics { topics }
            repeat(300) { i -> store.save(Thought(id="s_stress_$i",trigger=ThoughtTrigger.app,state=ThoughtState.done,
                title="Gedanke ${i+1}",text="Ein Gedanke zum Thema ${i%30+1} für die Leistungsprüfung.",topicId=topics[i%30].id,
                createdAt=now.minusSeconds(i*300L),tasks=if(i%7==0) listOf(ThoughtTask(id="k_stress_$i",text="Nächsten Schritt überlegen",owner=Owner.user)) else emptyList())) }
            repository.publish(store)
        } finally { repository.workMutex.unlock() }
    }

    @Test fun mapFocusPanelDetailListAndInbox() {
        seedMapExamples(); launch()
        node { it.contentDescription?.startsWith("Garten,")==true }.let(::click)
        node { it.text?.startsWith("Offen  ")==true }
        assertTrue(nodes().any { it.text?.contains("Töpfe besorgen")==true })
        node { it.contentDescription?.toString()=="Gedanke aufnehmen" }
        node { it.text?.toString()=="Aufgaben" }.let(::click)
        node { it.text?.toString()=="Gedanken" }.let(::click)
        node { it.contentDescription?.toString()=="Panel schließen" }
        node { it.contentDescription?.toString()=="Panel vergrößern" }.let(::click)
        node { it.text?.toString()=="Tomaten brauchen größere Töpfe" }.let(::click)
        node { it.contentDescription?.toString()=="Zurück" }.let(::click)
        node { it.contentDescription?.toString()=="Panel schließen" }.let(::click)
        node { it.contentDescription?.contains("im Eingang")==true }.let(::click)
        node { it.text?.toString()=="Noch nicht geordnet" }
        node { it.contentDescription?.toString()=="Panel schließen" }.let(::click)
        node { it.contentDescription?.toString()=="Liste zeigen" }.let(::click)
        node { it.text?.toString()=="Gedanken durchsuchen" }
        node { it.contentDescription?.toString()=="Karte zeigen" }.let(::click)
        node { it.contentDescription?.startsWith("Paply,")==true }
    }

    @Test fun pinchPanAndDoubleTapKeepRememberedPlaces()=runBlocking {
        seedMapExamples(); launch()
        node { it.contentDescription?.startsWith("Garten,")==true }
        val anchors=File(context.filesDir,"thoughts/map-anchors.json")
        val before=anchors.readBytes()
        pinch()
        node { it.contentDescription?.toString()=="Ganze Karte zeigen" }
        pan()
        assertArrayEquals(before,anchors.readBytes())
        node { it.contentDescription?.toString()=="Ganze Karte zeigen" }.let(::click)
        SystemClock.sleep(650)
        assertFalse(nodes().any { it.contentDescription?.toString()=="Ganze Karte zeigen" })
        doubleTapFree()
        node { it.contentDescription?.toString()=="Ganze Karte zeigen" }
        assertArrayEquals(before,anchors.readBytes())
    }

    @Test fun panelDragHasThreeStopsAndCloses() {
        seedMapExamples(); launch()
        node { it.contentDescription?.startsWith("Garten,")==true }.let(::click)
        fun panelHeight()=Rect().also(node { it.paneTitle?.toString()=="Garten" }::getBoundsInScreen).height()
        fun dragGrip(distance:Float) {
            val grip=Rect().also(node { it.contentDescription?.toString() in listOf("Panel vergrößern","Panel verkleinern") }::getBoundsInScreen)
            val x=grip.exactCenterX(); val y=grip.exactCenterY(); val at=SystemClock.uptimeMillis()
            send(MotionEvent.obtain(at,at,MotionEvent.ACTION_DOWN,x,y,0))
            repeat(20) { i -> SystemClock.sleep(16); send(MotionEvent.obtain(at,SystemClock.uptimeMillis(),MotionEvent.ACTION_MOVE,x,y+distance*(i+1)/20,0)) }
            send(MotionEvent.obtain(at,SystemClock.uptimeMillis(),MotionEvent.ACTION_UP,x,y+distance,0))
            SystemClock.sleep(700)
        }
        val medium=panelHeight()
        dragGrip(500f)
        assertTrue(panelHeight()<medium*.8)
        dragGrip(-1200f)
        assertTrue(panelHeight()>medium*1.5)
        node { it.contentDescription?.toString()=="Panel verkleinern" }
        dragGrip(1700f)
        assertFalse(nodes().any { it.contentDescription?.toString()=="Panel schließen" })
    }

    /** Optional screen capture harness; all screenshots are real device frames. */
    @Test fun captureMapEvidence() {
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("screenshots")=="true")
        val appearance=InstrumentationRegistry.getArguments().getString("appearance")?:"dark"
        seedMapExamples(); launch()
        node { it.contentDescription?.startsWith("Garten,")==true }; shot("overview-$appearance")
        node { it.contentDescription?.startsWith("Garten,")==true }.let(::click); shot("focus-$appearance")
        node { it.contentDescription?.toString()=="Panel vergrößern" }.let(::click); shot("panel-$appearance")
        node { it.text?.toString()=="Tomaten brauchen größere Töpfe" }.let(::click); shot("detail-$appearance")
        node { it.contentDescription?.toString()=="Zurück" }.let(::click)
        node { it.contentDescription?.toString()=="Panel schließen" }.let(::click)
        node { it.contentDescription?.contains("im Eingang")==true }.let(::click); shot("inbox-$appearance")
        node { it.contentDescription?.toString()=="Panel schließen" }.let(::click)
        node { it.contentDescription?.toString()=="Liste zeigen" }.let(::click); shot("list-$appearance")
        node { it.contentDescription?.toString()=="Karte zeigen" }.let(::click)
        pinch(); pan(); shot("gestures-$appearance")
        node { it.contentDescription?.toString()=="Ganze Karte zeigen" }.let(::click)
        seedStressExamples(); launch()
        node { it.contentDescription?.startsWith("Weitere Themen,")==true }; shot("stress-$appearance")
        node { it.contentDescription?.startsWith("Weitere Themen,")==true }.let(::click); shot("more-$appearance")
    }

    @Test fun showLargeFontPanel() {
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("screenshots")=="true")
        seedMapExamples(); launch()
        node { it.contentDescription?.startsWith("Garten,")==true }.let(::click)
        node { it.contentDescription?.toString()=="Panel vergrößern" }.let(::click)
        shot("large-font")
    }

    @Test fun profileStressGestures() {
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("profile")=="true")
        seedStressExamples(); launch()
        node { it.contentDescription?.startsWith("Weitere Themen,")==true }
        pinch(); pan()
        node { it.contentDescription?.toString()=="Ganze Karte zeigen" }.let(::click)
        fun shell(command:String)=android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use { it.readText() }
        shell("dumpsys gfxinfo com.paply.android reset")
        repeat(6) {
            pinch(); pan()
            node { it.contentDescription?.toString()=="Ganze Karte zeigen" }.let(::click)
        }
        val dir=requireNotNull(context.getExternalFilesDir("map-shots")).apply { mkdirs() }
        File(dir,"gfxinfo-stress.txt").writeText(shell("dumpsys gfxinfo com.paply.android"))
        File(dir,"gfxinfo-stress-framestats.txt").writeText(shell("dumpsys gfxinfo com.paply.android framestats"))
        File(dir,"layout-profile.txt").writeText(shell("logcat -d -s PaplyMap:D '*:S'"))
        shot("stress-profile")
    }

    private fun launch() {
        context.startActivity(Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        instrumentation.waitForIdleSync(); SystemClock.sleep(900)
    }
    private fun shot(name:String) {
        instrumentation.waitForIdleSync(); SystemClock.sleep(700)
        val bitmap=requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        val dir=requireNotNull(context.getExternalFilesDir("map-shots")).apply { mkdirs() }
        File(dir,"map-$name.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }; bitmap.recycle()
    }
    private fun nodes():List<AccessibilityNodeInfo> {
        instrumentation.uiAutomation.clearCache()
        val result=mutableListOf<AccessibilityNodeInfo>()
        fun visit(n:AccessibilityNodeInfo) { result+=n; repeat(n.childCount) { n.getChild(it)?.let(::visit) } }
        instrumentation.uiAutomation.rootInActiveWindow?.let(::visit)
        return result
    }
    private fun node(test:(AccessibilityNodeInfo)->Boolean):AccessibilityNodeInfo {
        val deadline=SystemClock.uptimeMillis()+10000
        while(SystemClock.uptimeMillis()<deadline) { nodes().firstOrNull(test)?.let { return it }; SystemClock.sleep(120) }
        error("Missing UI node: "+nodes().mapNotNull { it.text?:it.contentDescription }.joinToString(" | "))
    }
    private fun click(n:AccessibilityNodeInfo) {
        var bounds=Rect().also(n::getBoundsInScreen)
        var stable=0
        val until=SystemClock.uptimeMillis()+2500
        while(stable<3 && SystemClock.uptimeMillis()<until) {
            SystemClock.sleep(80)
            n.refresh()
            val current=Rect().also(n::getBoundsInScreen)
            stable=if(current==bounds && !current.isEmpty) stable+1 else 0
            bounds=current
        }
        check(!bounds.isEmpty) { "No visible bounds for ${n.text?:n.contentDescription}" }
        val down=SystemClock.uptimeMillis()
        send(MotionEvent.obtain(down,down,MotionEvent.ACTION_DOWN,bounds.exactCenterX(),bounds.exactCenterY(),0))
        SystemClock.sleep(60)
        send(MotionEvent.obtain(down,SystemClock.uptimeMillis(),MotionEvent.ACTION_UP,bounds.exactCenterX(),bounds.exactCenterY(),0))
        instrumentation.waitForIdleSync(); SystemClock.sleep(550)
    }
    private fun send(event:MotionEvent) { try { check(instrumentation.uiAutomation.injectInputEvent(event,true)) } finally { event.recycle() } }
    private fun doubleTapFree() {
        val map=Rect().also(node { it.contentDescription?.toString()=="Karte der Gedanken" }::getBoundsInScreen)
        val occupied=nodes().filter { it.contentDescription?.toString()?.matches(Regex(".*?, [0-9]+ Gedanken?.*"))==true }
            .map { Rect().also(it::getBoundsInScreen).apply { inset(-24,-60) } }
        val candidates=(25..80 step 5).flatMap { y -> (5..95 step 5).map { x -> map.left+map.width()*x/100f to map.top+map.height()*y/100f } }
        val point=candidates.first { (x,y) -> occupied.none { it.contains(x.toInt(),y.toInt()) } }
        repeat(2) {
            val at=SystemClock.uptimeMillis()
            send(MotionEvent.obtain(at,at,MotionEvent.ACTION_DOWN,point.first,point.second,0))
            SystemClock.sleep(40)
            send(MotionEvent.obtain(at,SystemClock.uptimeMillis(),MotionEvent.ACTION_UP,point.first,point.second,0))
            SystemClock.sleep(70)
        }
        SystemClock.sleep(700)
    }
    private fun pinch() {
        val display=context.resources.displayMetrics
        val x=display.widthPixels*.5f; val y=display.heightPixels*.43f
        val down=SystemClock.uptimeMillis()
        fun event(action:Int,count:Int,spread:Float) {
            val properties=Array(count) { i -> MotionEvent.PointerProperties().apply { id=i; toolType=MotionEvent.TOOL_TYPE_FINGER } }
            val coords=Array(count) { i -> MotionEvent.PointerCoords().apply { this.x=x+(if(i==0) -spread else spread); this.y=y; pressure=1f; size=1f } }
            send(MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,count,properties,coords,0,0,1f,1f,0,0,InputDevice.SOURCE_TOUCHSCREEN,0))
        }
        event(MotionEvent.ACTION_DOWN,1,50f)
        event(MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),2,50f)
        repeat(20) { SystemClock.sleep(16); event(MotionEvent.ACTION_MOVE,2,50f+it*8) }
        event(MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),2,202f)
        event(MotionEvent.ACTION_UP,1,202f)
        SystemClock.sleep(700)
    }
    private fun pan() {
        val display=context.resources.displayMetrics
        val x=display.widthPixels*.5f; val y=display.heightPixels*.4f
        val down=SystemClock.uptimeMillis()
        send(MotionEvent.obtain(down,down,MotionEvent.ACTION_DOWN,x,y,0))
        repeat(16) { i -> SystemClock.sleep(18); send(MotionEvent.obtain(down,SystemClock.uptimeMillis(),MotionEvent.ACTION_MOVE,x+i*9,y+i*5,0)) }
        send(MotionEvent.obtain(down,SystemClock.uptimeMillis(),MotionEvent.ACTION_UP,x+135,y+75,0))
        SystemClock.sleep(650)
    }
}
