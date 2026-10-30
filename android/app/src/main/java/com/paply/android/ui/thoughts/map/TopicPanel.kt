package com.paply.android.ui.thoughts.map

import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.staggeredgrid.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.*
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.nestedscroll.*
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.android.ui.thoughts.*
import java.time.Instant
import com.paply.thoughts.display.TaskAgenda
import kotlin.math.abs

/** An in-page panel, deliberately inside the tab and recording controls. */
@Composable
internal fun TopicPanel(id:String,content:MapContent,collected:Set<String>,actions:ThoughtsActions,detent:Int,
    onDetent:(Int)->Unit,small:Dp,medium:Dp,large:Dp,accessibility:MapAccessibility,onClose:()->Unit,
    onOpen:(String,String?)->Unit,onEdit:(String)->Unit,onSelect:(String)->Unit,modifier:Modifier=Modifier) {
    val density=LocalDensity.current
    val topic=content.topic(id)
    val members=remember(content,id,collected) { content.members(id,collected) }
    val tasks=remember(members) {
        members.flatMap { thought -> thought.tasks.filterNot { it.done }.map { thought to it } }
            .sortedWith(compareBy<Pair<com.paply.thoughts.Thought,com.paply.thoughts.ThoughtTask>> { it.second.dueAt?:Instant.MAX }
                .thenByDescending { it.first.createdAt })
    }
    var expanded by remember { mutableStateOf(false) }
    var drag by remember { mutableFloatStateOf(0f) }
    val heights=listOf(small,medium,large)
    val target=heights[detent]
    val animated by animateDpAsState(target,if(accessibility.reduce) snap() else spring(dampingRatio=1f,stiffness=300f),label="topic-panel")
    val actual=(animated-with(density) { drag.toDp() }).coerceIn(24.dp,large+12.dp)
    val tint=topicTint(topic?.id)
    val scroll=rememberLazyStaggeredGridState()
    val columns=if(detent==2 && density.fontScale<1.3f) 2 else 1
    var overscroll by remember { mutableFloatStateOf(0f) }
    val pullDown=remember(scroll,detent,accessibility.spoken) { object:NestedScrollConnection {
        override fun onPreScroll(available:Offset,source:NestedScrollSource):Offset {
            if(detent==2 && !accessibility.spoken && source==NestedScrollSource.UserInput && available.y>0 &&
                scroll.firstVisibleItemIndex==0 && scroll.firstVisibleItemScrollOffset==0) {
                overscroll+=available.y
                if(overscroll>with(density) { 70.dp.toPx() }) { overscroll=0f; onDetent(1) }
                return available
            }
            if(available.y<0) overscroll=0f
            return Offset.Zero
        }
        override suspend fun onPostFling(consumed:Velocity,available:Velocity):Velocity { overscroll=0f; return Velocity.Zero }
    } }
    LaunchedEffect(detent) { if(detent!=2) scroll.scrollToItem(0) }
    val dragGesture=Modifier.pointerInput(detent,small,medium,large) {
        detectVerticalDragGestures(onVerticalDrag={ change,amount -> change.consume(); drag+=amount },onDragCancel={ drag=0f },onDragEnd={
            val current=target-with(density) { drag.toDp() }
            if(current<small-44.dp) onClose()
            else onDetent(heights.indices.minBy { abs(heights[it].value-current.value) })
            drag=0f
        })
    }
    val shape=RoundedCornerShape(topStart=30.dp,topEnd=30.dp)
    Column(modifier.fillMaxWidth().height(actual).then(if(detent!=2) dragGesture else Modifier).clip(shape)
        .background(Color(0xFF11301F)).background(Brush.verticalGradient(listOf(tint.badge.copy(alpha=.18f),Color.Transparent),endY=with(density) { 160.dp.toPx() }))
        .border(.5.dp,Color.White.copy(alpha=.1f),shape).semantics { paneTitle=content.title(id) }) {
        Column(Modifier.fillMaxWidth().then(if(detent==2) dragGesture else Modifier).semantics {
            expand { onDetent(2); true }
            collapse { onDetent(0); true }
            dismiss { onClose(); true }
            customActions=listOf(CustomAccessibilityAction("Größer") { onDetent((detent+1).coerceAtMost(2)); true },
                CustomAccessibilityAction("Kleiner") { onDetent((detent-1).coerceAtLeast(0)); true },
                CustomAccessibilityAction("Schließen") { onClose(); true })
        }) {
            Box(Modifier.fillMaxWidth().height(21.dp).clickable { onDetent(if(detent==0) 1 else if(detent==1) 2 else 1) }
                .semantics { contentDescription=if(detent==2) "Ansicht verkleinern" else "Ansicht vergrößern" },contentAlignment=Alignment.Center) {
                Box(Modifier.size(36.dp,5.dp).background(Color.White.copy(alpha=.26f),RoundedCornerShape(3.dp)))
            }
            Row(Modifier.fillMaxWidth().padding(start=18.dp,end=10.dp,bottom=12.dp),verticalAlignment=Alignment.CenterVertically,
                horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                if(id==PENDING) Box(Modifier.size(44.dp).background(C.thoughtMint.copy(alpha=.14f),RoundedCornerShape(13.dp)),contentAlignment=Alignment.Center) {
                    Glyph(PaplyIcons.Sparkles,tint=C.thoughtMint,size=22.dp)
                } else TopicBadge(topic,44.dp)
                Column(Modifier.weight(1f)) {
                    Text(content.title(id),style=MaterialTheme.typography.titleLarge,color=C.text,maxLines=2,overflow=TextOverflow.Ellipsis,
                        modifier=Modifier.semantics { heading() })
                    Text("${members.size} ${if(members.size==1) "Gedanke" else "Gedanken"}" + if(tasks.isNotEmpty()) " · ${tasks.size} offen" else "",
                        style=MaterialTheme.typography.bodySmall,color=if(tasks.isNotEmpty()) C.thoughtGold else C.secondary)
                }
                if(topic!=null) IconButton(onClick={ onEdit(topic.id) }) { Glyph(PaplyIcons.More,"Thema bearbeiten",C.text) }
                IconButton(onClick=onClose) { Glyph(PaplyIcons.Close,"Ansicht schließen",C.text,18.dp) }
            }
        }
        if(detent!=0 || accessibility.spoken) LazyVerticalStaggeredGrid(columns=StaggeredGridCells.Fixed(columns),state=scroll,userScrollEnabled=detent==2 || accessibility.spoken,
            contentPadding=PaddingValues(start=12.dp,end=12.dp,bottom=28.dp),verticalItemSpacing=10.dp,
            horizontalArrangement=Arrangement.spacedBy(10.dp),modifier=Modifier.weight(1f).nestedScroll(pullDown)) {
            if(tasks.isNotEmpty()) {
                item("open-label",span=StaggeredGridItemSpan.FullLine) { Text("Offen  ${tasks.size}",style=MaterialTheme.typography.titleSmall,color=C.secondary,
                    modifier=Modifier.padding(start=6.dp,top=10.dp).semantics { heading() }) }
                item("open-tasks",span=StaggeredGridItemSpan.FullLine) {
                    PaplyCard(radius=18.dp) {
                        (if(expanded) tasks else tasks.take(3)).forEach { (thought,task) ->
                            val now=Instant.now()
                            val due=dueText(task,thought,now)
                            val dueColor=if(task.done || actions.pending[task.id]==true) C.secondary else when(TaskAgenda.group(task.dueAt,now)) {
                                TaskAgenda.Group.overdue -> C.beak
                                TaskAgenda.Group.today -> C.thoughtMint
                                else -> C.secondary
                            }
                            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
                                TaskCheck(task,thought.id,actions)
                                Column(Modifier.weight(1f).clickable { onOpen(thought.id,task.id) }.padding(vertical=8.dp)) {
                                    TaskText(task,actions)
                                    Text(thought.displayTitle,style=MaterialTheme.typography.bodySmall,color=C.secondary,
                                        maxLines=if(density.fontScale>=1.5f) 2 else 1,overflow=TextOverflow.Ellipsis)
                                    if(density.fontScale>=1.5f && due!=null) Text(due,style=MaterialTheme.typography.bodySmall,color=dueColor)
                                }
                                if(density.fontScale<1.5f && due!=null) Text(due,style=MaterialTheme.typography.bodyMedium,color=dueColor,
                                    maxLines=1,overflow=TextOverflow.Ellipsis,modifier=Modifier.widthIn(max=110.dp))
                            }
                        }
                        if(tasks.size>3) TextButton(onClick={ expanded=!expanded }) { Text(if(expanded) "Weniger zeigen" else "Alle ${tasks.size} zeigen") }
                    }
                }
            }
            if(id==com.paply.thoughts.map.MapLayout.moreID) {
                item("collected-label",span=StaggeredGridItemSpan.FullLine) { Text("Themen",style=MaterialTheme.typography.titleSmall,color=C.secondary,modifier=Modifier.semantics { heading() }) }
                items(collected.mapNotNull { content.topic(it) }.sortedBy { it.title },key={ "topic:${it.id}" },span={ StaggeredGridItemSpan.FullLine }) { t ->
                    Row(Modifier.fillMaxWidth().background(C.row,RoundedCornerShape(14.dp)).clickable { onSelect(t.id) }.padding(12.dp),
                        verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)) {
                        TopicBadge(t); Text(t.title,style=MaterialTheme.typography.titleSmall,modifier=Modifier.weight(1f))
                        Text("${members.count { content.topicOf[it.id]==t.id }}",color=C.secondary)
                    }
                }
            }
            item("thoughts-label",span=StaggeredGridItemSpan.FullLine) { Text("Gedanken",style=MaterialTheme.typography.titleSmall,color=C.secondary,
                modifier=Modifier.padding(start=6.dp,top=10.dp).semantics { heading() }) }
            // Two columns in the large detent; large type always gets one. Rows stay lazy for 300+ thoughts.
            val groups=if(members.size<=24) mapOf("" to members) else members.groupBy { sectionDate(it.createdAt) }
            groups.forEach { (title,thoughts) ->
                if(title.isNotEmpty()) item("date:$title",span=StaggeredGridItemSpan.FullLine) { Text(title,style=MaterialTheme.typography.bodySmall,color=C.secondary,modifier=Modifier.semantics { heading() }) }
                items(thoughts,key={ "card:${it.id}" }) { thought ->
                    var raw by remember(thought.id,thought.rev) { mutableStateOf<String?>(null) }
                    LaunchedEffect(thought.id,thought.rev) {
                        if(thought.state!=com.paply.thoughts.ThoughtState.done) {
                            try { raw=actions.repository.source(thought.id)?.text }
                            catch(e:kotlinx.coroutines.CancellationException) { throw e }
                            catch(_:Exception) { raw=null }
                        }
                    }
                    ThoughtCard(thought,actions,{ onOpen(thought.id,null) },raw=raw,compact=columns>1)
                }
            }
        }
    }
}
