package com.paply.android.ui.thoughts.map

import android.animation.ValueAnimator
import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.isSpecified
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.*
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.*
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.*
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.android.ui.thoughts.*
import com.paply.thoughts.*
import com.paply.thoughts.map.*
import kotlinx.coroutines.*
import java.io.File
import java.time.Instant
import kotlin.math.*

internal data class MapAccessibility(val reduce: Boolean, val spoken: Boolean)
@Composable
internal fun rememberMapAccessibility(): MapAccessibility {
    val context=LocalContext.current
    val manager=remember { context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager }
    var reduce by remember { mutableStateOf(!ValueAnimator.areAnimatorsEnabled()) }
    var spoken by remember { mutableStateOf(manager.isTouchExplorationEnabled) }
    DisposableEffect(context,manager) {
        val observer=object:ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) { reduce=!ValueAnimator.areAnimatorsEnabled() }
        }
        context.contentResolver.registerContentObserver(Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),false,observer)
        val listener=AccessibilityManager.TouchExplorationStateChangeListener { spoken=it }
        manager.addTouchExplorationStateChangeListener(listener)
        onDispose { context.contentResolver.unregisterContentObserver(observer); manager.removeTouchExplorationStateChangeListener(listener) }
    }
    return MapAccessibility(reduce,spoken)
}

@Stable
private class CameraState {
    var camera by mutableStateOf(MapCamera.identity)
    var moved by mutableStateOf(false)
    var overviewFree: MapCamera?=null
    var focusFree: Pair<String,MapCamera>?=null
    var animation: Job?=null
    fun resting(focus:String?) = if(focus==null) overviewFree else focusFree?.takeIf { it.first==focus }?.second
    fun store(focus:String?,value:MapCamera?) { if(focus==null) overviewFree=value else focusFree=value?.let { focus to it } }
    fun move(target:MapCamera,reduce:Boolean,scope:CoroutineScope) {
        animation?.cancel()
        val start=camera
        if(reduce) { camera=target; return }
        animation=scope.launch {
            animate(0f,1f,animationSpec=spring(dampingRatio=1f,stiffness=110f)) { value,_ ->
                val t=value.toDouble()
                camera=MapCamera(exp(ln(start.zoom)+(ln(target.zoom)-ln(start.zoom))*t),
                    MapPoint(start.center.x+(target.center.x-start.center.x)*t,start.center.y+(target.center.y-start.center.y)*t))
            }
        }
    }
}

/** The actual map slot. Home owns selection so panel and focus survive a detail/tab round trip. */
@Composable
fun ThoughtMapSlot(thoughts:List<Thought>,topics:List<Topic>,repository:ThoughtsRepository,actions:ThoughtsActions,
    focusedTopic:String?,onFocus:(String?)->Unit,onOpen:(String,String?)->Unit,onEditTopic:(String)->Unit,
    setup:@Composable ()->Unit={},setupProgress:Pair<Int,Int> = 0 to 0) {
    val context=LocalContext.current
    val allTopics by produceState(topics,topics) {
        try { value=repository.mapTopics() }
        catch(e:CancellationException) { throw e }
        catch(_:Exception) { value=topics }
    }
    val content=remember(thoughts,allTopics) { MapContent(thoughts,allTopics) }
    val input=remember(content) { content.input }
    val store=remember(repository) { MapSceneStore(File(context.filesDir,"thoughts/${MapAnchorFile.fileName}").toPath()) }
    val layout by produceState(MapLayout.empty,input) {
        try {
            val start=android.os.SystemClock.elapsedRealtime()
            value=store.layout(input)
            if(com.paply.android.BuildConfig.DEBUG) android.util.Log.d("PaplyMap",
                "layout thoughts=${input.thoughts.size} topics=${input.topics.size} computations=${store.computations} ms=${android.os.SystemClock.elapsedRealtime()-start}")
        }
        catch(e:CancellationException) { throw e }
        catch(_:Exception) { actions.message("Karte konnte nicht geladen werden. Bitte erneut öffnen.") }
    }
    val style=MapStyle(isSystemInDarkTheme())
    val accessibility=rememberMapAccessibility()
    val density=LocalDensity.current
    val camera=remember { CameraState() }
    val hits=remember { MapHits() }
    val scope=rememberCoroutineScope()
    var detent by rememberSaveable { mutableIntStateOf(1) }
    val collected=remember(layout,input) { if(layout.bubbles.isEmpty()) MapLayout.collected(input.topics) else layout.collected.toSet() }
    val selected=focusedTopic?.let { if(it.startsWith("_")) it else content.topic(it)?.id }
    LaunchedEffect(focusedTopic,content,layout) {
        if(focusedTopic!=null && (selected==null || content.members(selected,collected).isEmpty())) onFocus(null)
        else if(selected!=focusedTopic) onFocus(selected)
    }
    LaunchedEffect(selected) { if(selected!=null) detent=if(accessibility.spoken) 2 else 1 }
    BackHandler(selected!=null) { onFocus(null) }
    BoxWithConstraints(Modifier.fillMaxSize().background(style.ground)) {
        val full=maxHeight
        val small=(96.dp*density.fontScale.coerceAtMost(2f)).coerceAtMost(full-40.dp)
        val medium=maxOf(full*.5f,small+100.dp).coerceAtMost(full-70.dp)
        val large=full-4.dp
        val panelHeight=when(detent) { 0->small; 2->large; else->medium }
        val covered=if(selected==null) 0.dp else minOf(panelHeight,medium)
        val focus=selected?.takeIf { layout.bubble(it)!=null }
        var headerHeight by remember { mutableStateOf(0.dp) }
        val geometry=remember(layout,maxWidth,maxHeight,covered,focus,headerHeight,selected) {
            val top=if(selected==null) headerHeight.value.toDouble() else 0.0
            val g=mapGeometry(layout,maxWidth.value.toDouble(),maxHeight.value.toDouble()-top,covered.value.toDouble(),focus)
            if(top>0) g.copy(visible=g.visible.copy(y=top),viewport=g.viewport.copy(visible=g.visible.copy(y=top))) else g
        }
        LaunchedEffect(geometry,focus,accessibility.spoken,accessibility.reduce) {
            if(camera.focusFree?.first!=focus) camera.focusFree=null
            val home=if(accessibility.spoken) geometry.overview else geometry.home
            val free=if(accessibility.spoken) null else camera.resting(focus)?.let { geometry.viewport.clamped(it) }
            camera.store(focus,free)
            camera.moved=free?.let { geometry.viewport.differs(it,home) } == true
            camera.move(free?:home,accessibility.reduce,scope)
        }
        val landings=remember { MapLandings() }
        var flights by remember { mutableStateOf(emptyList<MapLandings.Flight>()) }
        var inboxCount by remember { mutableIntStateOf(content.pending.size) }
        val clock=remember { mutableStateOf(Instant.now()) }
        LaunchedEffect(content,layout,selected,accessibility.reduce) {
            var now=Instant.now()
            clock.value=now
            landings.observe(content.pending.map { it.id }.toSet(),thoughts.map { it.id }.toSet(),now)
            landings.place(!accessibility.reduce && selected==null,now) { id ->
                content.topicOf[id]?.let { if(it in collected) MapLayout.moreID else it }?.takeIf { layout.bubble(it)!=null }
            }
            flights=if(accessibility.reduce || selected!=null) emptyList() else landings.flights.toList()
            inboxCount=if(accessibility.reduce || selected!=null) content.pending.size else landings.count(now)
            while(flights.isNotEmpty() && landings.isRunning(now)) {
                withFrameNanos { }
                now=Instant.now(); clock.value=now
                val count=landings.count(now)
                if(inboxCount!=count) inboxCount=count
            }
            flights=emptyList()
        }
        val select:(String)->Unit={ onFocus(it) }
        val open:(String)->Unit={ onOpen(it,null) }
        val latestSelect by rememberUpdatedState(select)
        val latestOpen by rememberUpdatedState(open)
        val latestClose by rememberUpdatedState { onFocus(null) }
        val gestures=Modifier
            .pointerInput(geometry,focus,accessibility.reduce,accessibility.spoken) {
                var lastTap=0L
                var lastPoint=Offset.Zero
                var deselect:Job?=null
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed=false)
                    val up=waitForUpOrCancellation()
                    if(up!=null) {
                        val p=up.position/density.density
                        val time=up.uptimeMillis
                        if(hits.hit(p,focus,latestSelect,latestOpen)) {
                            deselect?.cancel(); lastTap=0L
                        } else if(time-lastTap<320 && (p-lastPoint).getDistance()<44 && !accessibility.spoken) {
                            deselect?.cancel(); lastTap=0L
                            val at=MapPoint(p.x.toDouble(),p.y.toDouble())
                            val next=geometry.viewport.doubleTapped(camera.camera,at)
                            camera.store(focus,next)
                            camera.moved=next?.let { geometry.viewport.differs(it,geometry.home) } == true
                            camera.move(next?:geometry.home,accessibility.reduce,scope)
                        } else {
                            lastTap=time; lastPoint=p
                            deselect?.cancel()
                            if(selected!=null) deselect=scope.launch { delay(320); latestClose() }
                        }
                    }
                }
            }
            .pointerInput(geometry,focus,accessibility.reduce,accessibility.spoken) {
                if(accessibility.spoken) return@pointerInput
                awaitEachGesture {
                    val down=awaitFirstDown(requireUnconsumed=false)
                    var raw=camera.camera
                    var changed=false
                    var pinched=false
                    var totalPan=Offset.Zero
                    var totalZoom=1f
                    var anchor=MapPoint((down.position.x/density.density).toDouble(),(down.position.y/density.density).toDouble())
                    val tracker=VelocityTracker()
                    tracker.addPosition(down.uptimeMillis,down.position)
                    do {
                        val event=awaitPointerEvent()
                        val zoom=event.calculateZoom()
                        val pan=event.calculatePan()
                        val centroid=event.calculateCentroid(useCurrent=false)
                        totalPan+=pan; totalZoom*=zoom
                        val count=event.changes.count { it.pressed }
                        if(count>1) pinched=true
                        if(!changed && (totalPan.getDistance()>viewConfiguration.touchSlop || abs(1-totalZoom)*100>viewConfiguration.touchSlop)) {
                            changed=true; camera.animation?.cancel()
                        }
                        if(changed && centroid.isSpecified) {
                            anchor=MapPoint((centroid.x/density.density).toDouble(),(centroid.y/density.density).toDouble())
                            raw=geometry.viewport.zoomed(raw,raw.zoom*zoom,anchor)
                            raw=geometry.viewport.panned(raw,MapSize((pan.x/density.density).toDouble(),(pan.y/density.density).toDouble()))
                            camera.camera=geometry.viewport.rubberBanded(raw,anchor)
                            camera.moved=geometry.viewport.differs(camera.camera,geometry.home)
                            event.changes.forEach { if(it.positionChanged()) it.consume() }
                        }
                        event.changes.firstOrNull()?.let { tracker.addPosition(it.uptimeMillis,it.position) }
                    } while(event.changes.any { it.pressed })
                    if(changed) {
                        var target=geometry.viewport.settled(raw,anchor)
                        if(!pinched && !geometry.viewport.differs(raw,target)) {
                            val velocity=tracker.calculateVelocity()
                            if(hypot(velocity.x,velocity.y)/density.density>220) target=geometry.viewport.flung(target,
                                MapSize((velocity.x/density.density).toDouble(),(velocity.y/density.density).toDouble()))
                        }
                        val moved=geometry.viewport.differs(target,geometry.home)
                        camera.store(focus,if(moved) target else null); camera.moved=moved
                        camera.move(if(moved) target else geometry.home,accessibility.reduce,scope)
                    }
                }
            }
        MapCanvas(content,layout,style,geometry,focus,{ camera.camera },hits,select,open,gestures,
            flights={ flights },now={ clock.value })
        if(selected==null) Column(Modifier.align(Alignment.TopCenter).fillMaxWidth().padding(horizontal=16.dp)
            .onSizeChanged { headerHeight=with(density) { it.height.toDp() } }) {
            Box(if(style.dark) Modifier else Modifier.background(C.forest,androidx.compose.foundation.shape.RoundedCornerShape(18.dp))) {
                ThoughtsHomeHeader(setupProgress.first,setupProgress.second,setup)
            }
        }
        if(layout.bubbles.isEmpty()) Column(Modifier.align(Alignment.Center).padding(28.dp),horizontalAlignment=Alignment.CenterHorizontally) {
            Text(if(content.pending.isNotEmpty()) "Dein Gedanke wird geordnet …" else "Noch keine Gedanken",color=style.ink,style=MaterialTheme.typography.titleMedium)
            Text("Mit jedem Gedanken wächst deine Karte.",color=style.secondary,style=MaterialTheme.typography.bodyMedium)
        }
        if(selected==null && inboxCount>0) MapInboxOrb(inboxCount,MapInboxStatus.of(content.pending.map { it.state })?:MapInboxStatus.ordering,
            style,accessibility.reduce,content.pending.any { it.state == com.paply.thoughts.ThoughtState.waitingKey && it.status.message?.contains("ungültig") == true },{ onFocus(PENDING) },Modifier.align(Alignment.BottomCenter))
        else if(selected==null && content.placed.size<=12 && !camera.moved) Text(
            if(content.placed.size<=2) "Mit jedem Gedanken wächst deine Karte." else "Größer = mehr Gedanken · Linien = gehört zusammen",
            color=style.tertiary,style=MaterialTheme.typography.bodySmall,modifier=Modifier.align(Alignment.BottomCenter).padding(16.dp))
        if(camera.moved && !accessibility.spoken) FilledTonalIconButton(onClick={
            camera.store(focus,null); camera.moved=false; camera.move(geometry.home,accessibility.reduce,scope)
        },modifier=Modifier.align(Alignment.BottomEnd).padding(end=12.dp,bottom=covered+8.dp)) {
            Glyph(PaplyIcons.Scan,if(focus==null) "Ganze Karte zeigen" else "Thema ganz zeigen",style.ink)
        }
        if(selected!=null) key(selected) {
            TopicPanel(selected,content,collected,actions,detent,{ detent=it },small,medium,large,accessibility,
                onClose={ onFocus(null) },onOpen=onOpen,onEdit=onEditTopic,onSelect={ onFocus(it) },modifier=Modifier.align(Alignment.BottomCenter))
        }
    }
}

@Composable
private fun MapInboxOrb(count:Int,status:MapInboxStatus,style:MapStyle,reduce:Boolean,keyRejected:Boolean,onClick:()->Unit,modifier:Modifier) {
    val text=when(status) {
        MapInboxStatus.ordering->"Wird geordnet …"; MapInboxStatus.network->"Wartet auf Netz"; MapInboxStatus.key->if(keyRejected) "Schlüssel ungültig" else "Schlüssel fehlt"
        MapInboxStatus.limit->"Groq-Limit, später"; MapInboxStatus.budget->"Kontingent erreicht"; MapInboxStatus.attention->"Nicht verschriftlicht"
    }
    val active=status==MapInboxStatus.ordering
    val alpha=if(active && !reduce) {
        val transition=rememberInfiniteTransition(label="inbox")
        val value by transition.animateFloat(.4f,.8f,infiniteRepeatable(tween(1500),RepeatMode.Reverse),label="inbox-glow")
        value
    } else if(active) .42f else .18f
    Column(modifier.clickable(onClick=onClick).semantics(mergeDescendants=true) {
        contentDescription="$count ${if(count==1) "Gedanke" else "Gedanken"} im Eingang, $text"; role=Role.Button
    }.padding(horizontal=16.dp,vertical=7.dp).heightIn(min=48.dp),horizontalAlignment=Alignment.CenterHorizontally) {
        Box(Modifier.size(28.dp).drawBehind {
            drawCircle(Brush.radialGradient(listOf(C.green.copy(alpha=alpha*.5f),Color.Transparent),radius=size.minDimension),radius=size.minDimension)
            drawCircle(Brush.radialGradient(if(active) listOf(Color(0xFF9AF5BC),C.greenBright,C.greenDeep) else
                listOf(C.green.copy(alpha=.75f),C.greenDeep.copy(alpha=.85f),C.forest),center=center-Offset(size.width*.16f,size.height*.2f),radius=size.minDimension*.82f),radius=size.minDimension/2)
        }.border(.6.dp,Color.White.copy(alpha=if(active) .22f else .12f),CircleShape),contentAlignment=Alignment.Center) {
            Text("$count",color=if(active) C.recordInk else C.text,style=MaterialTheme.typography.labelMedium)
        }
        Text(text,color=style.secondary,style=MaterialTheme.typography.labelSmall)
    }
}
