package com.paply.thoughts.store

import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.*
import java.nio.file.StandardOpenOption.*
import java.util.UUID

object FileSafety {
    const val tempPrefix = ".tmp-"

    fun createDirectory(url: Path) {
        Files.createDirectories(url)
    }

    /**
     * Android must exclude the supplied root in backup rules and use credential-protected app
     * storage.
     */
    fun writeAtomically(data: ByteArray, to: Path) {
        val temp = to.resolveSibling(tempPrefix + UUID.randomUUID() + "-" + to.fileName)
        try {
            FileChannel.open(temp, WRITE, CREATE_NEW).use { channel ->
                val buffer = ByteBuffer.wrap(data)
                while (buffer.hasRemaining()) channel.write(buffer)
                channel.force(true)
            }
            Files.move(
                temp,
                to,
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
        } finally {
            Files.deleteIfExists(temp)
        }
    }

    /** A failed directory sync propagates: callers must retain audio. */
    fun syncDirectory(url: Path) {
        FileChannel.open(url, READ).use { it.force(true) }
    }

    fun exists(url: Path) = Files.exists(url, LinkOption.NOFOLLOW_LINKS)

    fun fileSize(url: Path): Long? =
        try {
            Files.size(url)
        } catch (_: java.io.IOException) {
            null
        }
}
