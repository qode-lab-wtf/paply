package com.paply.android.settings

import android.annotation.SuppressLint
import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** AES key never leaves Android Keystore. Only IV + authenticated ciphertext enter private prefs. */
class KeyVault(context: Context) {
    private val app = context.applicationContext
    private val prefs = app.getSharedPreferences("paply-key-vault", Context.MODE_PRIVATE)

    /** Thin synchronous adapter for the IME/service integration. Never logs or caches plaintext. */
    fun read(): String? = synchronized(lock) {
        // Keep migration inside the caller's error boundary, including Keystore/storage failures.
        migrateLegacy()
        decrypt()
    }

    @SuppressLint("UseKtx") // A success must mean the encrypted value is durable.
    fun save(value: String) = synchronized(lock) {
        val key = value.trim()
        require(key.isNotEmpty())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(key.toByteArray(Charsets.UTF_8))
        check(prefs.edit().putString("iv", encode(cipher.iv)).putString("ciphertext", encode(encrypted)).commit())
        removeLegacy()
        Unit
    }

    @SuppressLint("UseKtx")
    fun remove() = synchronized(lock) {
        check(prefs.edit().clear().commit())
        removeLegacy()
        Unit
    }

    private fun decrypt(): String? {
        val encrypted = prefs.getString("ciphertext", null) ?: return null
        val iv = requireNotNull(prefs.getString("iv", null))
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        // Missing/unusable Keystore material is an error, never silently a new key or empty vault.
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val key = requireNotNull(store.getKey(ALIAS, null) as? SecretKey)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, decode(iv)))
        return String(cipher.doFinal(decode(encrypted)), Charsets.UTF_8)
    }

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }

    private fun migrateLegacy() {
        val old = app.getSharedPreferences("paply-private", Context.MODE_PRIVATE).getString("groq", null)
        if (!old.isNullOrBlank() && !prefs.contains("ciphertext")) save(old)
        else if (old != null) {
            // Verify an existing encrypted key before deleting a legacy copy after a crash.
            if (prefs.contains("ciphertext")) decrypt()
            removeLegacy()
        }
    }

    @SuppressLint("UseKtx")
    private fun removeLegacy() {
        val old = app.getSharedPreferences("paply-private", Context.MODE_PRIVATE)
        if (old.contains("groq")) check(old.edit().remove("groq").commit())
    }

    private fun encode(bytes: ByteArray) = Base64.encodeToString(bytes, Base64.NO_WRAP)
    private fun decode(value: String) = Base64.decode(value, Base64.NO_WRAP)

    companion object {
        private const val ALIAS = "paply.groq.aes256.v1"
        private val lock = Any()
    }
}
