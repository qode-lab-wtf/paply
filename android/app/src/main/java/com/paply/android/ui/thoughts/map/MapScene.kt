package com.paply.android.ui.thoughts.map

import androidx.compose.runtime.*
import com.paply.android.ui.thoughts.displayTitle
import com.paply.android.ui.thoughts.openTaskCount
import com.paply.thoughts.*
import com.paply.thoughts.map.*
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.nio.file.Path
import java.time.Instant
import kotlin.math.*

internal const val NO_TOPIC = "_none"
internal const val PENDING = "_pending"

/** Model snapshot, independent of the camera and the animation clock. */
internal data class MapContent(val thoughts: List<Thought>, val topics: List<Topic>) {
    val topicsByID = topics.associateBy { it.id }
    val thoughtsByID = thoughts.associateBy { it.id }
    fun topic(id: String?): Topic? {
        var next = id
        val seen = mutableSetOf<String>()
        while (next != null && seen.add(next)) {
            val topic = topicsByID[next] ?: return null
            if (topic.mergedInto == null) return topic
            next = topic.mergedInto
        }
        return null
    }
    val pending = thoughts.filter { MapInboxStatus.isPending(it.state) }
    val placed = thoughts.filterNot { MapInboxStatus.isPending(it.state) }
    val topicOf = placed.associate { it.id to (topic(it.topicId)?.id ?: NO_TOPIC) }
    val input: MapLayoutInput by lazy {
        val grouped = placed.groupBy { topicOf.getValue(it.id) }
        val few = placed.size <= 5
        val entries = topics.filter { it.mergedInto == null }.map { t ->
            val items = grouped[t.id].orEmpty()
            MapLayoutInput.Topic(t.id, items.size, items.maxOfOrNull { it.createdAt } ?: t.createdAt,
                if (few) items.size else 0, t.owner == Owner.user)
        } + MapLayoutInput.Topic(NO_TOPIC, grouped[NO_TOPIC].orEmpty().size,
            grouped[NO_TOPIC]?.maxOfOrNull { it.createdAt } ?: Instant.MIN,
            if (few) grouped[NO_TOPIC].orEmpty().size else 0)
        return@lazy MapLayoutInput(entries, placed.map { MapLayoutInput.Thought(it.id, topicOf.getValue(it.id), it.createdAt) },
            placed.flatMap { t -> t.links.filter { it.target in topicOf }.map { MapLayoutInput.Link(t.id, it.target) } })
    }
    fun members(id: String, collected: Set<String>): List<Thought> = when (id) {
        PENDING -> pending
        MapLayout.moreID -> placed.filter { topicOf[it.id] in collected }
        NO_TOPIC -> placed.filter { topicOf[it.id] == NO_TOPIC }
        else -> thoughts.filter { topic(it.topicId)?.id == id }
    }
    fun title(id: String) = when (id) {
        NO_TOPIC -> "Ohne Thema"
        PENDING -> "Noch nicht geordnet"
        MapLayout.moreID -> "Weitere Themen"
        else -> topic(id)?.title.orEmpty()
    }
}

/** Serial IO and revision checks mirror MapAnchors on iOS. Never overwrites an unreadable file. */
internal class MapSceneStore(private val file: Path) {
    private val anchors = MapAnchorState(false)
    private val mutex=Mutex()
    private var settled: MapLayoutInput? = null
    private var layout = MapLayout.empty
    var computations=0
        private set
    suspend fun layout(input: MapLayoutInput): MapLayout = mutex.withLock { withContext(Dispatchers.Default) {
        if (!anchors.isReady || anchors.phase is MapAnchorState.Phase.Blocked) {
            val loaded = withContext(Dispatchers.IO) { MapAnchorFile.load(file) }
            anchors.apply(loaded, Instant.now())
        }
        val request = input.copy(anchors = anchors.anchors)
        if (request != settled) {
            val revision = anchors.revision
            val computed = MapLayout.compute(request)
            computations++
            ensureActive() // An obsolete calculation must neither publish nor remember its anchors.
            withContext(Dispatchers.IO) {
                ensureActive()
                // No suspension between the in-memory commit and the atomic file write. The mutex
                // keeps a replacement request from observing a half-committed anchor state.
                if (anchors.remember(computed.anchors, revision)) MapAnchorFile.save(anchors.anchors, file)
            }
            ensureActive()
            layout = computed
            settled = request.copy(anchors = computed.anchors)
        }
        layout
    } }
}

internal data class MapGeometry(val visible: MapRect, val home: MapCamera, val overview: MapCamera, val viewport: MapViewport)

/** iOS ThoughtMapView camera formulas, in dp/map points rather than physical pixels. */
internal fun mapGeometry(layout: MapLayout, width: Double, height: Double, covered: Double, focus: String?): MapGeometry {
    val visible = MapRect(0.0, 0.0, width.coerceAtLeast(1.0), (height - covered).coerceAtLeast(120.0))
    val anchor = MapPoint(visible.midX, visible.midY)
    val area = visible.inset(18.0, 12.0).let { it.copy(height = max(40.0, it.height - 40)) }
    val bounds = layout.bounds
    val zoom = if (bounds.width > 0 && bounds.height > 0) max(.05, min(1.8, min(area.width / bounds.width, area.height / bounds.height))) else 1.0
    val overview = MapCamera(zoom, MapPoint(bounds.midX - (area.midX - anchor.x) / zoom, bounds.midY - (area.midY - anchor.y) / zoom))
    val bubble = focus?.let { layout.bubble(it) }
    val home = if (bubble != null) {
        val own = layout.dots.filter { it.topicID == focus }.sortedBy { it.rank }
        val spacing = if (own.size >= 2) hypot(own[0].position.x - own[1].position.x, own[0].position.y - own[1].position.y) else 22.0
        val fit = min((visible.width - 44) / (2 * bubble.outerRadius), (visible.height - 36) / (bubble.outerRadius + bubble.radius))
        MapCamera(max(.5, min(fit, min(2.2, maxOf(1.35, 26 / max(spacing, 1.0), overview.zoom * 1.25)))),
            MapPoint(bubble.center.x, bubble.center.y - (bubble.outerRadius - bubble.radius) / 2))
    } else overview
    return MapGeometry(visible, home, overview, MapViewport(visible, bounds, overview.zoom))
}
