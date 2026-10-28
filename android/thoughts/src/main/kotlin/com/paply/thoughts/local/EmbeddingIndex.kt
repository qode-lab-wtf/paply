package com.paply.thoughts.local

import com.paply.thoughts.nlp.Embedder

/** V1 deliberately ships no embedding model, downloads or persistent embeddings.bin. */
class EmbeddingIndex : Embedder {
    override val available = false

    override fun embed(text: String, language: String?): Embedder.Vector? = null
}
