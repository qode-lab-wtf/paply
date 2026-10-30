package com.paply.android.ui.thoughts.map

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import com.paply.android.ui.components.PaplyIcons
import com.paply.android.ui.thoughts.*
import com.paply.thoughts.map.*
import kotlin.math.*

internal class MapHit(id: String, topic: String?, center: Offset, radius: Float,
    rect: Rect? = null, spacing: Double = Double.POSITIVE_INFINITY) {
    val id=id
    val topic=topic
    val center=center
    val radius=radius
    val rect=rect
    val spacing=spacing
}
internal class MapHits {
    var topics: List<MapHit> = emptyList()
    var dots: List<MapHit> = emptyList()
    var titles: List<MapHit> = emptyList()
    fun hit(point: Offset, focus: String?, onTopic: (String) -> Unit, onThought: (String) -> Unit): Boolean {
        fun distance(hit: MapHit) = (hit.center - point).getDistance()
        titles.filter { it.rect?.inflate(5f)?.contains(point) == true }.minByOrNull(::distance)?.let { onThought(it.id); return true }
        dots.filter { it.topic == focus && focus != null && distance(it) <= 26 }.minByOrNull(::distance)?.let { onThought(it.id); return true }
        topics.filter { distance(it) <= max(24f,it.radius+8) }.minByOrNull { distance(it)-it.radius }
            ?.let { onTopic(it.id); return true }
        topics.firstOrNull { it.rect?.inflate(8f)?.contains(point) == true }?.let { onTopic(it.id); return true }
        dots.filter { distance(it) <= 22 }.minByOrNull(::distance)?.let {
            if (focus == null && it.spacing >= 28) onThought(it.id) else onTopic(it.topic!!)
            return true
        }
        return false
    }
}

private class TopicDrawing(colors: BubbleColors, painter: Painter, image: ImageBitmap?, label: TextLayoutResult, orb:ImageBitmap, glow:ImageBitmap) {
    val colors=colors
    val painter=painter
    val image=image
    val label=label
    val orb=orb
    val glow=glow
}
private class DotDrawing(title: TextLayoutResult, open: Boolean) {
    val title=title
    val open=open
}

/** Only this draw lambda reads the moving camera; scene, text and images stay cached while gesturing. */
@Composable
internal fun MapCanvas(content: MapContent, layout: MapLayout, style: MapStyle, geometry: MapGeometry,
    focus: String?, camera: () -> MapCamera, hits: MapHits, onTopic: (String) -> Unit, onThought: (String) -> Unit,
    modifier: Modifier = Modifier, flights: () -> List<MapLandings.Flight> = { emptyList() },
    now: () -> java.time.Instant = { java.time.Instant.now() }) {
    val density = LocalDensity.current
    val textMeasurer = rememberTextMeasurer(cacheSize = 256)
    val mapTextDensity=remember(density) { Density(density.density,density.fontScale.coerceAtMost(1.35f)) }
    val appearance = LocalTopicAppearance.current
    val topics = layout.bubbles.associate { bubble ->
        val tint = topicTint(bubble.id)
        val colors = style.bubble(tint)
        val vector = when (bubble.id) {
            NO_TOPIC -> PaplyIcons.CircleDashed
            MapLayout.moreID -> PaplyIcons.List
            else -> content.topic(bubble.id)?.icon?.glyph ?: PaplyIcons.Sparkles
        }
        val painter = rememberVectorPainter(vector)
        val image = remember(appearance.images[bubble.id]) { appearance.images[bubble.id]?.asImageBitmap() }
        val title = content.title(bubble.id)
        val label = remember(title, bubble.count, style, density) {
            textMeasurer.measure(buildAnnotatedString {
                append(title)
                withStyle(SpanStyle(color=style.secondary,fontWeight=FontWeight.Medium)) { append("  ${bubble.count}") }
            },
                TextStyle(color=style.ink, fontSize=13.sp, fontWeight=FontWeight.SemiBold),
                overflow=TextOverflow.Ellipsis, maxLines=1, density=mapTextDensity, constraints=Constraints(maxWidth=with(density) { 136.dp.roundToPx() }))
        }
        val orb=remember(colors) { orbTexture(colors) }
        val glow=remember(colors.dot) { dotTexture(colors.dot) }
        bubble.id to TopicDrawing(colors,painter,image,label,orb,glow)
    }
    val dots = remember(layout, content.thoughts, style, density) {
        layout.dots.associate { dot ->
            val thought = content.thoughtsByID[dot.id]
            dot.id to DotDrawing(textMeasurer.measure(AnnotatedString(thought?.displayTitle.orEmpty()),
                TextStyle(color=style.ink.copy(alpha=.86f),fontSize=12.sp), maxLines=1, overflow=TextOverflow.Ellipsis, density=mapTextDensity,
                constraints=Constraints(maxWidth=with(density) { 164.dp.roundToPx() })), thought?.openTaskCount?.let { it>0 } == true)
        }
    }
    val ownDots = remember(layout) { layout.dots.groupBy { it.topicID }.mapValues { (_,ds) -> ds.sortedBy { it.rank } } }
    val collected = remember(layout) { layout.collected.toSet() }
    val orderedDots=remember(layout,focus) { layout.dots.sortedWith(compareBy<com.paply.thoughts.map.MapLayout.Dot> { if(it.topicID==focus) 0 else 1 }.thenBy { it.rank }.thenBy { it.id }) }
    val gridTexture=remember(style) { MapGridTexture(style.grid) }
    // This layer has no camera reads, so Compose records its background only once.
    Canvas(Modifier.fillMaxSize()) {
        drawRect(style.ground)
        drawRect(Brush.radialGradient(if(style.dark) listOf(Color(0xFF1D4A35),style.ground,Color(0xFF08160F)) else
            listOf(Color.White.copy(alpha=.95f),style.ground),center=Offset(size.width*.5f,if(style.dark) -size.height*.08f else size.height*.52f),radius=max(size.width,size.height)*1.1f))
    }
    Canvas(modifier.fillMaxSize().clipToBounds().semantics { contentDescription = "Karte der Gedanken" }) {
        val dp = density.density
        val cam = camera()
        val zoom = cam.zoom.toFloat()
        fun screen(p: MapPoint): Offset {
            val s = geometry.viewport.screen(p,cam)
            return Offset(s.x.toFloat(), s.y.toFloat())
        }
        val width = size.width / dp
        val height = size.height / dp
        val topicHits = ArrayList<MapHit>(layout.bubbles.size)
        val dotHits = ArrayList<MapHit>(layout.dots.size)
        val titleHits = ArrayList<MapHit>()
        val time = now()
        val flying = flights()
        val hidden = flying.filter { it.land > time }.map { it.id }.toSet()
        val dotAlpha = if (content.placed.size <= 5) 1f else ((zoom-.95f)/.05f).coerceIn(0f,1f)
        withTransform({ scale(dp,dp,Offset.Zero) }) {
            var grid = 24f*zoom
            while (grid < 18) grid *= 2
            while (grid >= 36) grid /= 2
            val origin=screen(MapPoint.zero)
            drawIntoCanvas { gridTexture.draw(it.nativeCanvas,width,height,grid,origin.x,origin.y) }
            fun line(from: MapPoint, control: MapPoint, to: MapPoint, a: String, b: String, alpha: Float, stroke: Float) {
                val p=Path().apply { val f=screen(from); val c=screen(control); val t=screen(to); moveTo(f.x,f.y); quadraticTo(c.x,c.y,t.x,t.y) }
                val ca=topics[a]?.colors?.line ?: style.neutral
                val cb=topics[b]?.colors?.line ?: style.neutral
                drawPath(p,lerp(ca,cb,.5f).copy(alpha=alpha),style=Stroke(stroke,cap=StrokeCap.Round))
            }
            if (focus == null) layout.topicLines.forEach { l -> line(l.from,l.control,l.to,l.a,l.b,.18f,1.15f) }
            else layout.lines.filter { (it.topicA==focus || it.topicB==focus) && !it.touchesHidden }.forEach { l ->
                line(l.from,l.control,l.to,l.topicA,l.topicB,if(l.crossTopic) .55f else .72f,if(l.crossTopic) .9f else 1.3f)
            }
            layout.bubbles.forEach { b ->
                val d=topics.getValue(b.id)
                val center=screen(b.center)
                val radius=b.radius.toFloat()*zoom
                if(center.x+radius < -150 || center.x-radius > width+150 || center.y+radius < -80 || center.y-radius > height+80) return@forEach
                val alpha=if(focus!=null && focus!=b.id) .18f else 1f
                val neutral=b.id==NO_TOPIC || b.id==MapLayout.moreID
                if (!neutral) {
                    val extent=radius*2.25f
                    translate(center.x-extent,center.y-extent) {
                        scale(extent*2/d.orb.width,extent*2/d.orb.height,Offset.Zero) { drawImage(d.orb,alpha=alpha) }
                    }
                    if(d.image!=null) {
                        val path=Path().apply { addOval(Rect(center-Offset(radius,radius),Size(radius*2,radius*2))) }
                        clipPath(path) { drawImage(d.image,dstOffset=IntOffset((center.x-radius).roundToInt(),(center.y-radius).roundToInt()),
                            dstSize=IntSize((radius*2).roundToInt().coerceAtLeast(1),(radius*2).roundToInt().coerceAtLeast(1)),alpha=alpha) }
                    }
                    drawCircle(d.colors.body.copy(alpha=.38f*alpha),radius,center,style=Stroke(if(d.image!=null) 1.8f else .6f))
                } else {
                    drawCircle(style.neutral.copy(alpha=.04f*alpha),radius,center)
                    drawCircle(style.neutral.copy(alpha=.65f*alpha),radius,center,style=Stroke(1f,pathEffect=if(b.id==NO_TOPIC) PathEffect.dashPathEffect(floatArrayOf(3f,4f)) else null))
                }
                if(b.id==MapLayout.moreID) {
                    listOf(Triple(-.2f,.14f,.2f),Triple(.22f,.1f,.15f),Triple(.02f,-.24f,.12f)).forEach { (x,y,r) ->
                        drawCircle(style.neutral.copy(alpha=.75f*alpha),radius*r,center+Offset(x*radius,y*radius))
                    }
                }
                if(d.image==null && !neutral) {
                    val iconSize=(radius*1.2f).coerceIn(13f,72f)
                    translate(center.x-iconSize/2,center.y-iconSize/2) { with(d.painter) { draw(Size(iconSize,iconSize),alpha,ColorFilter.tint(if(neutral) style.neutral else d.colors.glyph)) } }
                }
                val own=ownDots[b.id].orEmpty()
                if (dotAlpha < 1f && b.id != focus && own.size>1) {
                    val arcRadius=(b.radius+12).toFloat()*zoom
                    val start=own.minOf { it.angle }.toFloat()*180f/PI.toFloat()
                    val sweep=(own.maxOf { it.angle }-own.minOf { it.angle }).toFloat()*180f/PI.toFloat()
                    drawArc(d.colors.dot.copy(alpha=.22f*alpha*(1-dotAlpha)),start,sweep,false,
                        center-Offset(arcRadius,arcRadius),Size(arcRadius*2,arcRadius*2),style=Stroke(1.2f))
                }
                val labelTop=center.y+radius+8
                var labelRect: Rect?=null
                if(focus==null) {
                    // Text was measured in physical pixels; draw it at its original size, independent of zoom.
                    val labelSize=Size(d.label.size.width/dp,d.label.size.height/dp)
                    labelRect=Rect(Offset(center.x-labelSize.width/2,labelTop),labelSize)
                    drawRoundRect(style.ground.copy(alpha=.84f),labelRect.topLeft-Offset(3f,1f),Size(labelRect.width+6f,labelRect.height+2f),CornerRadius(4f))
                    withTransform({ scale(1/dp,1/dp,Offset.Zero) }) { drawText(d.label,topLeft=labelRect.topLeft*dp,alpha=alpha) }
                    if(content.placed.size<=5) own.take(b.titleLines).forEachIndexed { index,dot ->
                        val text=dots[dot.id]?.title ?: return@forEachIndexed
                        val top=labelTop+labelSize.height+4+index*(text.size.height/dp+2)
                        val rect=Rect(Offset(center.x-text.size.width/dp/2,top),Size(text.size.width/dp,text.size.height/dp))
                        drawRoundRect(style.ground.copy(alpha=.85f),rect.topLeft-Offset(3f,1f),Size(rect.width+6f,rect.height+2f),CornerRadius(4f))
                        withTransform({ scale(1/dp,1/dp,Offset.Zero) }) { drawText(text,topLeft=rect.topLeft*dp) }
                        titleHits.add(MapHit(dot.id,b.id,rect.center,0f,rect))
                    }
                }
                topicHits.add(MapHit(b.id,null,center,radius,labelRect))
            }
            orderedDots.forEach { dot ->
                if(dot.id in hidden) return@forEach
                val focused=dot.topicID==focus
                val shown=if(focused) 1f else dotAlpha
                if(shown<=.01f) return@forEach
                val p=screen(dot.position)
                if(p.x < -30 || p.x>width+30 || p.y < -30 || p.y>height+30) return@forEach
                val info=dots.getValue(dot.id)
                val alpha=shown*(if(focus!=null && !focused) .18f else 1f)
                val color=topics[dot.topicID]?.colors?.dot ?: style.neutral
                val radius=if(focused) (2.64f*zoom).coerceIn(3.4f,6.2f) else (2.97f*zoom).coerceIn(1.5f,3.4f)
                drawCircle(style.ground.copy(alpha=alpha),radius+2,p)
                if(info.open) drawCircle(style.open.copy(alpha=alpha),radius+2.5f,p,style=Stroke(1.3f))
                if(content.thoughtsByID[dot.id]?.createdAt?.let { java.time.Duration.between(it,time).seconds<86400 }==true)
                    topics[dot.topicID]?.glow?.let { texture ->
                        val extent=radius+6
                        translate(p.x-extent,p.y-extent) {
                            scale(extent*2/texture.width,extent*2/texture.height,Offset.Zero) { drawImage(texture,alpha=alpha) }
                        }
                    }
                drawCircle(color.copy(alpha=alpha),radius,p)
                val own=ownDots[dot.topicID].orEmpty()
                val spacing=if(own.size>=2) hypot(own[0].position.x-own[1].position.x,own[0].position.y-own[1].position.y)*zoom else Double.POSITIVE_INFINITY
                dotHits.add(MapHit(dot.id,dot.topicID,p,radius,spacing=spacing))
                val threshold=when(dot.rank) { 0->1.5; in 1..2->1.95; in 3..5->2.45; in 6..11->3.1; else->3.8 }
                if(content.placed.size>5 && ((focused && (dot.rank<3 || info.open)) || (focus==null && zoom>threshold+.18))) {
                    val tw=info.title.size.width/dp
                    val th=info.title.size.height/dp
                    val gap=radius+7
                    val cosine=cos(dot.angle)
                    val left=when { cosine<-.35 -> p.x-gap-tw; cosine>.35 -> p.x+gap; else -> p.x-tw/2 }
                    val top=if(abs(cosine)>.35) p.y-th/2 else p.y-radius-5-th
                    val rect=Rect(Offset(left,top),Size(tw,th))
                    val area=Rect(8f,geometry.visible.minY.toFloat()+6,width-8,geometry.visible.maxY.toFloat()-6)
                    if(rect.left<area.left || rect.right>area.right || rect.top<area.top || rect.bottom>area.bottom) return@forEach
                    if(titleHits.any { it.rect?.inflate(3f)?.overlaps(rect)==true } || topicHits.any { it.rect?.inflate(3f)?.overlaps(rect)==true }) return@forEach
                    if(topicHits.any { hit ->
                        val q=Offset(hit.center.x.coerceIn(rect.left,rect.right),hit.center.y.coerceIn(rect.top,rect.bottom))
                        (hit.center-q).getDistance()<hit.radius+4
                    }) return@forEach
                    if(own.any { other ->
                        val point=screen(other.position)
                        val q=Offset(point.x.coerceIn(rect.left,rect.right),point.y.coerceIn(rect.top,rect.bottom))
                        (point-q).getDistance()<radius+3
                    }) return@forEach
                    drawRoundRect(style.ground.copy(alpha=.9f),rect.topLeft-Offset(3f,2f),Size(rect.width+6f,rect.height+4f),CornerRadius(4f))
                    withTransform({ scale(1/dp,1/dp,Offset.Zero) }) { drawText(info.title,topLeft=rect.topLeft*dp,alpha=alpha) }
                    titleHits.add(MapHit(dot.id,dot.topicID,rect.center,0f,rect))
                }
            }
            flying.forEach { flight ->
                val progress=flight.progress(time) ?: return@forEach
                val target=layout.dots.firstOrNull { it.id==flight.id }?.position ?: layout.bubble(flight.topicID)?.center ?: return@forEach
                val end=screen(target)
                val start=Offset(width/2,geometry.visible.maxY.toFloat()-35)
                val w=6.5; val t=((1-(1+w*progress)*exp(-w*progress))/(1-(1+w)*exp(-w))).toFloat()
                val pos=Offset(start.x+(end.x-start.x)*t,start.y+(end.y-start.y)*t-24*sin(PI*t).toFloat())
                val color=topics[flight.topicID]?.colors?.dot ?: style.neutral
                drawCircle(color.copy(alpha=.16f),10f,pos); drawCircle(color,3f,pos)
            }
        }
        hits.topics=topicHits; hits.dots=dotHits; hits.titles=titleHits
    }
    // Invisible semantic peers use the very same projection as the canvas. No extra scene or layout calculation.
    Layout(content={
        layout.bubbles.forEach { bubble ->
            val members=content.members(bubble.id,collected)
            val open=members.sumOf { it.openTaskCount }
            androidx.compose.foundation.layout.Box(Modifier.semantics {
                contentDescription="${content.title(bubble.id)}, ${bubble.count} ${if(bubble.count==1) "Gedanke" else "Gedanken"}" + if(open>0) ", $open ${if(open==1) "offene Aufgabe" else "offene Aufgaben"}" else ""
                role=Role.Button; selected=focus==bubble.id
                onClick("Gedanken dieses Themas zeigen") { onTopic(bubble.id); true }
            })
        }
    },modifier=Modifier.fillMaxSize()) { measurables,constraints ->
        val cam=camera()
        val placeables=measurables.mapIndexed { i,m ->
            val side=max(48.0,layout.bubbles[i].radius*cam.zoom*2).dp.roundToPx()
            m.measure(Constraints.fixed(side,side))
        }
        layout(constraints.maxWidth,constraints.maxHeight) {
            placeables.forEachIndexed { i,p ->
                val point=geometry.viewport.screen(layout.bubbles[i].center,cam)
                p.place((point.x*density.density-p.width/2).roundToInt(),(point.y*density.density-p.height/2).roundToInt())
            }
        }
    }
}
