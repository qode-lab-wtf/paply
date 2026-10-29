package com.paply.android.ui.thoughts.map

import com.paply.thoughts.*
import com.paply.thoughts.map.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files
import java.time.Instant

class MapSceneTest {
    private val now=Instant.parse("2026-10-29T00:00:00Z")
    private val topic=Topic("t_a","Garten",TopicIcon.leaf,Owner.user,now)
    private fun thought(id:String,topicID:String?=topic.id,state:ThoughtState=ThoughtState.done)=
        Thought(id=id,trigger=ThoughtTrigger.app,state=state,createdAt=now,topicId=topicID,title=id)

    @Test fun inboxHasNoMapDotsOrOrphanLinksAndAliasesFollowTheirTarget() {
        val alias=Topic("t_old","Früher",TopicIcon.home,Owner.ai,now,mergedInto=topic.id)
        val pending=thought("s_wait",state=ThoughtState.waitingKey)
        val a=thought("s_a",alias.id).copy(links=listOf(ThoughtLink("s_wait",LinkKind.sameMatter,"",Owner.user),ThoughtLink("s_b",LinkKind.sameMatter,"",Owner.user)))
        val content=MapContent(listOf(a,thought("s_b",null),pending),listOf(topic,alias))
        assertEquals(setOf("s_wait"),content.pending.map { it.id }.toSet())
        assertEquals(listOf(MapLayoutInput.Link("s_a","s_b")),content.input.links)
        assertEquals(topic.id,content.topicOf["s_a"])
        assertEquals(NO_TOPIC,content.topicOf["s_b"])
        assertEquals(listOf(a,pending),content.members(topic.id,emptySet()))
        assertEquals(listOf(pending),content.members(PENDING,emptySet()))
        assertFalse(content.input.topics.any { it.id==alias.id })
    }

    @Test fun collectionAndPanelUseExactlyTheSameMembershipAt300Thoughts() {
        val topics=(0 until 30).map { topic.copy(id="t_$it",title="Thema $it") }
        val thoughts=(0 until 300).map { thought("s_$it",topics[it%30].id) }
        val content=MapContent(thoughts,topics)
        val layout=MapLayout.compute(content.input)
        assertTrue(layout.collected.isNotEmpty())
        val members=content.members(MapLayout.moreID,layout.collected.toSet())
        assertEquals(layout.bubble(MapLayout.moreID)!!.count,members.size)
        assertEquals(300,layout.bubbles.sumOf { it.count })
        assertTrue(layout.lines.isEmpty()); assertTrue(layout.topicLines.isEmpty())
    }

    @Test fun positionsSurviveStoreRecreationAndTopicGrowthWithoutSavingCamera() = runBlocking {
        val directory=Files.createTempDirectory("map-scene")
        try {
            val file=directory.resolve(MapAnchorFile.fileName)
            val input=MapContent(listOf(thought("s_a")),listOf(topic)).input
            val first=MapSceneStore(file).layout(input)
            val grown=MapContent((0..15).map { thought("s_$it") },listOf(topic)).input
            val next=MapSceneStore(file).layout(grown)
            assertEquals(first.bubble(topic.id)!!.center,next.bubble(topic.id)!!.center)
            assertEquals(first.anchors,next.anchors)
            assertTrue(MapAnchorFile.load(file) is MapAnchorFile.Loaded.Anchors)
            val json=Files.readString(file)
            assertFalse(json.contains("zoom")); assertFalse(json.contains("camera"))
        } finally { directory.toFile().deleteRecursively() }
    }

    @Test fun identicalGeometryReusesLayoutAcrossDisplayOnlyChanges() = runBlocking {
        val directory=Files.createTempDirectory("map-cache")
        try {
            val store=MapSceneStore(directory.resolve(MapAnchorFile.fileName))
            val original=thought("s_a")
            val first=store.layout(MapContent(listOf(original),listOf(topic)).input)
            val edited=original.copy(title="Neuer Titel",tasks=listOf(ThoughtTask(text="Neue Aufgabe",owner=Owner.user)))
            val next=store.layout(MapContent(listOf(edited),listOf(topic)).input)
            assertSame(first,next)
            assertEquals(1,store.computations)
        } finally { directory.toFile().deleteRecursively() }
    }

    @Test fun unreadableAnchorsAreNeverOverwritten() = runBlocking {
        val directory=Files.createTempDirectory("map-unreadable")
        try {
            val target=directory.resolve("private.json")
            Files.writeString(target,"keep me")
            val file=directory.resolve(MapAnchorFile.fileName)
            Files.createSymbolicLink(file,target)
            val layout=MapSceneStore(file).layout(MapContent(listOf(thought("s_a")),listOf(topic)).input)
            assertFalse(layout.bubbles.isEmpty())
            assertEquals("keep me",Files.readString(target))
            assertTrue(Files.isSymbolicLink(file))
        } finally { directory.toFile().deleteRecursively() }
    }

    @Test fun focusFitsAbovePanelAndPanNeverMutatesAnchors() {
        val layout=MapLayout.compute(MapContent((0..8).map { thought("s_$it") },listOf(topic)).input)
        val g=mapGeometry(layout,412.0,640.0,320.0,topic.id)
        val bubble=layout.bubble(topic.id)!!
        val center=g.viewport.screen(bubble.center,g.home)
        assertTrue(center.y-bubble.outerRadius*g.home.zoom>=0)
        assertTrue(center.y+bubble.radius*g.home.zoom<=g.visible.maxY)
        val before=layout.anchors.toMap()
        g.viewport.flung(g.viewport.zoomed(g.home,3.0,center),MapSize(600.0,200.0))
        assertEquals(before,layout.anchors)
    }
}
