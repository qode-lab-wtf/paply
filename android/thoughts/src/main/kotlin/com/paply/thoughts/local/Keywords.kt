package com.paply.thoughts.local

import com.paply.core.Lexicon
import com.paply.core.TextAnalysis
import com.paply.thoughts.nlp.LexicalAnalyzer
import com.paply.thoughts.nlp.SnowballLemmatizer
import com.paply.thoughts.nlp.TopicMentions
import kotlin.math.ln

/** Snowball replaces Apple's lemma/POS service; ranking and word weights remain separate. */
object Keywords {
    private val analyzer = SnowballLemmatizer()

    fun terms(text: String, language: String?, lexical: LexicalAnalyzer = analyzer): List<String> =
        lexical.analyze(text, language).flatMap { token ->
            val original = fold(token.original)
            // No POS model: remove closed-class words before stemming. German capitalization
            // alone is not evidence of a proper name; nouns must share their inflection stem.
            if (
                original in stopwords ||
                    original in functionWords ||
                    token.normalized in Lexicon.fillers
            )
                return@flatMap emptyList()
            val stems =
                if (language == null)
                    listOfNotNull(
                        analyzer.stem(token.normalized, "de"),
                        analyzer.stem(token.normalized, "en"),
                    )
                else listOf(token.stem ?: token.original)
            val forms = stems.map(::fold).toMutableSet()
            if (token.isName) forms.add(original) // preserve original name spelling alongside stems
            val acronym =
                token.original.length >= 2 &&
                    token.original == token.original.uppercase() &&
                    token.original != token.original.lowercase()
            forms.filter { folded ->
                folded.codePoints().anyMatch(TextAnalysis::isLetter) &&
                    (folded.length >= 3 ||
                        acronym && folded.length >= 2 ||
                        TextAnalysis.containsScriptioContinua(folded)) &&
                    folded !in stopStems &&
                    folded !in functionWords &&
                    folded !in Lexicon.fillers
            }
        }

    fun counts(terms: List<String>): Map<String, Int> = terms.groupingBy { it }.eachCount()

    fun top(counts: Map<String, Int>, limit: Int, idf: (String) -> Double = { 1.0 }): List<String> =
        counts
            .map { it.key to (1 + ln(it.value.toDouble())) * idf(it.key) }
            .sortedWith(compareByDescending<Pair<String, Double>> { it.second }.thenBy { it.first })
            .take(limit.coerceAtLeast(0))
            .map { it.first }

    fun fold(word: String) = TopicMentions.fold(word)

    internal val stopwords =
        listOf(
                "sein",
                "haben",
                "werden",
                "können",
                "müssen",
                "sollen",
                "wollen",
                "dürfen",
                "mögen",
                "möchten",
                "machen",
                "tun",
                "geben",
                "gehen",
                "kommen",
                "sagen",
                "lassen",
                "meinen",
                "glauben",
                "denken",
                "finden",
                "wissen",
                "heißen",
                "bleiben",
                "stehen",
                "liegen",
                "brauchen",
                "sehen",
                "nehmen",
                "halten",
                "bringen",
                "ding",
                "dinge",
                "sache",
                "sachen",
                "mal",
                "art",
                "weise",
                "bisschen",
                "teil",
                "zeit",
                "jahr",
                "tag",
                "also",
                "halt",
                "eben",
                "quasi",
                "irgendwie",
                "okay",
                "gut",
                "ja",
                "nein",
                "doch",
                "noch",
                "schon",
                "be",
                "have",
                "do",
                "will",
                "would",
                "can",
                "could",
                "shall",
                "should",
                "may",
                "might",
                "must",
                "get",
                "go",
                "make",
                "say",
                "want",
                "need",
                "think",
                "know",
                "let",
                "take",
                "see",
                "come",
                "give",
                "thing",
                "things",
                "stuff",
                "way",
                "lot",
                "kind",
                "sort",
                "time",
                "yeah",
                "okay",
                "like",
                "just",
                "être",
                "avoir",
                "faire",
                "aller",
                "pouvoir",
                "vouloir",
                "devoir",
                "chose",
                "ser",
                "estar",
                "haber",
                "tener",
                "hacer",
                "poder",
                "querer",
                "cosa",
                "essere",
                "avere",
                "fare",
                "andare",
                "potere",
                "volere",
                "dovere",
            )
            .map(::fold)
            .toSet()
    // Closed-class words that Apple's lexical tags omit (not a sentence/domain-specific lexicon).
    private val functionWords =
        """
        der die das den dem des ein eine einer eines einem einen und oder aber auch nur sowie bzw
        mit ohne für fuer von vom zum zur bei beim auf aus über unter nach vor seit bis gegen durch
        um ums als wie was wer wen wem wessen wo wohin woher wann warum weil dass da wenn ob obwohl
        ich mich mir mein meine meiner meines meinem meinen du dich dir dein deine deiner deinem deinen
        wir uns unser unsere unserer unseres unserem unseren ihr euch euer eure euren er ihn ihm
        sie ihnen ihre ihrer ihrem ihren ihres sein seine seiner seinem seinen seines man es sich
        dieser diese dieses diesem diesen jener jene jenes jedem jeder jede jedes allen alle alles
        bin bist ist sind seid war waren wart gewesen habe hast hat habt hatte hatten wird wirst
        wurde wurden würde würden kann kannst konnte könnten muss musst musste müssten soll sollte
        darf durfte mag möchte wollt wollte nicht nichts kein keine keinen keinem keiner keines
        hier dort dazu davon dabei dann denn sonst so damit deshalb trotzdem wieder mehr sehr viel
        viele vielen etwas etwa einmal immer jetzt heute morgen gestern bald schon noch ja nein
        the and or but a an of for with without from to at in on by into over under between through
        i me my mine we us our ours you your yours he him his she her hers it its they them their theirs
        this that these those who whom whose which what where when why how if because as than then
        is are am was were been being has had having does did doing can cannot could would should
        not no any all each every some such both either neither other another there here so too
        very more most much many only again now today tomorrow yesterday always never already yet
        """
            .trimIndent()
            .split(Regex("\\s+"))
            .map(::fold)
            .toSet()
    private val stopStems =
        (stopwords + functionWords)
            .flatMap { word ->
                listOf(
                    word,
                    fold(analyzer.stem(word, "de") ?: word),
                    fold(analyzer.stem(word, "en") ?: word),
                )
            }
            .toSet()
}
