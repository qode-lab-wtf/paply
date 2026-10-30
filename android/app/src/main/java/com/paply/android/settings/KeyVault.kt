package com.paply.android.settings

import android.annotation.SuppressLint
import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.paply.core.sanitizeApiKey
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class PermanentVaultKeyException(message: String) : GeneralSecurityException(message)

internal data class EncryptedKey(val iv: ByteArray, val ciphertext: ByteArray)
internal interface VaultStorage {
    fun encrypted(): EncryptedKey?
    fun write(value: EncryptedKey)
    fun clear()
    fun legacy(): String?
    fun removeLegacy()
}
internal interface VaultCryptography {
    fun encrypt(value: String): EncryptedKey
    fun decrypt(value: EncryptedKey): String
    fun deleteKey()
    fun createKey()
}

/** Synchronous IO adapter. Call off the UI thread; plaintext is never cached or logged. */
class KeyVault internal constructor(private val storage: VaultStorage, private val crypto: VaultCryptography) {
    constructor(context: Context) : this(PreferenceVaultStorage(context.applicationContext), KeystoreCryptography())

    fun read(): String? = synchronized(lock) {
        // A failed migration must never leave the old plaintext secret behind.
        try {
            val legacy = storage.legacy()?.let(::sanitizeApiKey)?.takeIf { it.isNotEmpty() }
            val existing = try {
                storage.encrypted()?.let { encrypted -> retryTransient { crypto.decrypt(encrypted) } }
            } catch (e: Exception) {
                if (!e.isPermanentKeyFailure()) throw e
                repair()
                if (legacy != null) {
                    storage.write(crypto.encrypt(legacy))
                    return@synchronized legacy
                }
                throw GeneralSecurityException("Schlüssel nicht mehr lesbar. Bitte neu eintragen.", e)
            }
            if (existing != null) existing
            else legacy?.also { storage.write(encryptWithRepair(it)) }
        } finally { storage.removeLegacy() }
    }

    fun save(value: String) = synchronized(lock) {
        try {
            val key = sanitizeApiKey(value)
            require(key.isNotEmpty())
            storage.write(encryptWithRepair(key))
        } finally { storage.removeLegacy() }
    }

    fun remove() = synchronized(lock) {
        // Attempt every cleanup even when one storage operation fails.
        try { storage.clear() }
        finally { try { storage.removeLegacy() } finally { crypto.deleteKey() } }
    }

    private fun encryptWithRepair(value: String): EncryptedKey = try { retryTransient { crypto.encrypt(value) } }
    catch (e: Exception) {
        if (!e.isPermanentKeyFailure()) throw e
        repair()
        crypto.encrypt(value) // Exactly one retry, including when the new key also fails.
    }

    private fun repair() {
        crypto.deleteKey()
        storage.clear() // Old ciphertext cannot be decrypted with the replacement key.
        crypto.createKey()
    }

    private fun <T> retryTransient(operation: () -> T): T = try { operation() }
    catch (e: Exception) {
        if (e.isPermanentKeyFailure()) throw e
        operation() // Provider/service/authentication failures never authorize deleting a key.
    }

    private fun Throwable.isPermanentKeyFailure(): Boolean =
        generateSequence(this) { it.cause }.take(16).any {
            it is android.security.keystore.KeyPermanentlyInvalidatedException || it is PermanentVaultKeyException
        }

    companion object { private val lock = Any() }
}

@SuppressLint("UseKtx") // Returning success must mean the value/removal is durable.
private class PreferenceVaultStorage(context: Context) : VaultStorage {
    private val prefs = context.getSharedPreferences("paply-key-vault", Context.MODE_PRIVATE)
    private val old = context.getSharedPreferences("paply-private", Context.MODE_PRIVATE)
    override fun encrypted(): EncryptedKey? {
        val ciphertext = prefs.getString("ciphertext", null) ?: return null
        val iv = requireNotNull(prefs.getString("iv", null))
        return EncryptedKey(Base64.decode(iv, Base64.NO_WRAP), Base64.decode(ciphertext, Base64.NO_WRAP))
    }
    override fun write(value: EncryptedKey) {
        check(prefs.edit().putString("iv", Base64.encodeToString(value.iv, Base64.NO_WRAP))
            .putString("ciphertext", Base64.encodeToString(value.ciphertext, Base64.NO_WRAP)).commit())
    }
    override fun clear() { check(prefs.edit().clear().commit()) }
    override fun legacy(): String? = old.getString("groq", null)
    override fun removeLegacy() { if (old.contains("groq")) check(old.edit().remove("groq").commit()) }
}

internal class KeystoreCryptography(private val alias: String = "paply.groq.aes256.v1") : VaultCryptography {
    private fun store() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    override fun encrypt(value: String): EncryptedKey {
        val existing = store().getKey(alias, null)
        if (existing != null && existing !is SecretKey) throw PermanentVaultKeyException("Unusable vault key")
        val key = existing ?: generateKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key) }
        return EncryptedKey(cipher.iv, cipher.doFinal(value.toByteArray(Charsets.UTF_8)))
    }
    override fun decrypt(value: EncryptedKey): String {
        val key = store().getKey(alias, null) as? SecretKey ?: throw PermanentVaultKeyException("Missing vault key")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, value.iv))
        }
        return String(cipher.doFinal(value.ciphertext), Charsets.UTF_8)
    }
    override fun deleteKey() { store().deleteEntry(alias) }
    override fun createKey() { generateKey() }
    private fun generateKey(): SecretKey = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
        init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true).build())
    }.generateKey()
}
