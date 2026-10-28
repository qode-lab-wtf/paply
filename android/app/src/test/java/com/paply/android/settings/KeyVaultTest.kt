package com.paply.android.settings

import java.security.InvalidKeyException
import org.junit.Assert.*
import org.junit.Test

class KeyVaultTest {
    private class Storage : VaultStorage {
        var value: EncryptedKey? = null
        var plaintext: String? = null
        var failWrite = false
        var failClear = false
        var failLegacyRead = false
        override fun encrypted() = value
        override fun write(value: EncryptedKey) { check(!failWrite); this.value = value }
        override fun clear() { check(!failClear); value = null }
        override fun legacy(): String? { check(!failLegacyRead); return plaintext }
        override fun removeLegacy() { plaintext = null }
    }
    private class Crypto : VaultCryptography {
        var badDecrypt = false
        var badEncryptions = 0
        var deletes = 0
        var creates = 0
        var encryptions = 0
        override fun encrypt(value: String): EncryptedKey {
            encryptions++
            if (badEncryptions-- > 0) throw InvalidKeyException()
            return EncryptedKey(byteArrayOf(1), value.toByteArray())
        }
        override fun decrypt(value: EncryptedKey): String {
            if (badDecrypt) throw InvalidKeyException()
            return String(value.ciphertext)
        }
        override fun deleteKey() { deletes++ }
        override fun createKey() { creates++ }
    }
    private fun sealedValue(value: String = "test-secret") = EncryptedKey(byteArrayOf(1), value.toByteArray())

    @Test fun saveSanitizesBeforeEncrypting() {
        val storage = Storage(); val crypto = Crypto(); val vault = KeyVault(storage, crypto)
        vault.save("  test-\u200Bsecret\u00A0\n")
        assertEquals("test-secret", vault.read())
        assertEquals(0, crypto.deletes)
    }
    @Test fun unusableEncryptionAliasIsReplacedOnce() {
        val storage = Storage(); val crypto = Crypto().apply { badEncryptions = 1 }
        KeyVault(storage, crypto).save("test-secret")
        assertEquals(1, crypto.deletes); assertEquals(1, crypto.creates)
        assertEquals(2, crypto.encryptions)
        assertNotNull(storage.value)
    }
    @Test fun secondEncryptionFailureDoesNotLoopAndDeletesLegacy() {
        val storage = Storage().apply { plaintext = "old-secret" }
        val crypto = Crypto().apply { badEncryptions = 2 }
        try { KeyVault(storage, crypto).read(); fail() } catch (_: InvalidKeyException) { }
        assertEquals(1, crypto.creates); assertEquals(2, crypto.encryptions)
        assertNull(storage.plaintext)
    }
    @Test fun damagedCiphertextWithoutLegacyResetsToEmptyVault() {
        val storage = Storage().apply { value = sealedValue() }
        val crypto = Crypto().apply { badDecrypt = true }
        assertNull(KeyVault(storage, crypto).read())
        assertNull(storage.value)
        assertEquals(1, crypto.deletes); assertEquals(1, crypto.creates)
    }
    @Test fun damagedCiphertextWithLegacyReencryptsAndRemovesPlaintext() {
        val storage = Storage().apply { value = sealedValue(); plaintext = "old-secret" }
        val crypto = Crypto().apply { badDecrypt = true }
        assertEquals("old-secret", KeyVault(storage, crypto).read())
        assertEquals("old-secret", String(storage.value!!.ciphertext)); assertNull(storage.plaintext)
        assertEquals(1, crypto.creates)
    }
    @Test fun healthyEncryptedValueWinsOverLegacyCopy() {
        val storage = Storage().apply { value = sealedValue(); plaintext = "stale-secret" }
        assertEquals("test-secret", KeyVault(storage, Crypto()).read())
        assertNull(storage.plaintext)
    }
    @Test fun migrationWriteFailureStillDeletesLegacy() {
        val storage = Storage().apply { plaintext = "old-secret"; failWrite = true }
        try { KeyVault(storage, Crypto()).read(); fail() } catch (_: IllegalStateException) { }
        assertNull(storage.plaintext)
    }
    @Test fun failedLegacyReadStillAttemptsPlaintextRemoval() {
        val storage = Storage().apply { plaintext = "old-secret"; failLegacyRead = true }
        try { KeyVault(storage, Crypto()).read(); fail() } catch (_: IllegalStateException) { }
        assertNull(storage.plaintext)
    }
    @Test fun removeDeletesCiphertextLegacyAndAlias() {
        val storage = Storage().apply { value = sealedValue(); plaintext = "old-secret" }
        val crypto = Crypto()
        KeyVault(storage, crypto).remove()
        assertNull(storage.value); assertNull(storage.plaintext); assertEquals(1, crypto.deletes)
    }
    @Test fun failedPreferenceRemovalStillAttemptsAliasAndLegacyRemoval() {
        val storage = Storage().apply { plaintext = "old-secret"; failClear = true }
        val crypto = Crypto()
        try { KeyVault(storage, crypto).remove(); fail() } catch (_: IllegalStateException) { }
        assertNull(storage.plaintext); assertEquals(1, crypto.deletes)
    }
}
