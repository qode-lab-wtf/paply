package com.paply.android.settings

import java.security.GeneralSecurityException
import java.security.ProviderException
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
        var decryptions = 0
        var transientFailures = 0
        var failure: Exception = ProviderException("temporarily unavailable")
        override fun encrypt(value: String): EncryptedKey {
            encryptions++
            if (transientFailures-- > 0) throw failure
            if (badEncryptions-- > 0) throw PermanentVaultKeyException("missing")
            return EncryptedKey(byteArrayOf(1), value.toByteArray())
        }
        override fun decrypt(value: EncryptedKey): String {
            decryptions++
            if (transientFailures-- > 0) throw failure
            if (badDecrypt) throw PermanentVaultKeyException("missing")
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
        try { KeyVault(storage, crypto).read(); fail() } catch (_: PermanentVaultKeyException) { }
        assertEquals(1, crypto.creates); assertEquals(2, crypto.encryptions)
        assertNull(storage.plaintext)
    }
    @Test fun permanentlyLostKeyRepairsButReportsThatUserMustReenterIt() {
        val storage = Storage().apply { value = sealedValue() }
        val crypto = Crypto().apply { badDecrypt = true }
        try { KeyVault(storage, crypto).read(); fail("must report permanent loss") } catch (_: GeneralSecurityException) { }
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
    @Test fun transientReadFailureRetriesOnceWithoutDeletingAnything() {
        val storage = Storage().apply { value = sealedValue() }
        val old = storage.value
        val crypto = Crypto().apply { transientFailures = 1 }
        assertEquals("test-secret", KeyVault(storage, crypto).read())
        assertSame(old, storage.value)
        assertEquals(2, crypto.decryptions); assertEquals(0, crypto.deletes); assertEquals(0, crypto.creates)
    }
    @Test fun persistentTransientAndMalformedCiphertextFailuresPreserveEncryptedValue() {
        for (error in listOf(ProviderException(), java.security.InvalidKeyException(),
            javax.crypto.AEADBadTagException(), IllegalArgumentException(),
            java.security.UnrecoverableKeyException("backend unavailable").apply { initCause(ProviderException()) })) {
            val storage = Storage().apply { value = sealedValue() }
            val old = storage.value
            val crypto = Crypto().apply { transientFailures = 2; failure = error }
            try { KeyVault(storage, crypto).read(); fail("must report read failure") } catch (actual: Exception) { assertSame(error, actual) }
            assertSame(old, storage.value)
            assertEquals(2, crypto.decryptions); assertEquals(0, crypto.deletes); assertEquals(0, crypto.creates)
        }
    }
    @Test fun transientSaveFailureRetriesWithoutReplacingAliasOrLosingPreviousValue() {
        val storage = Storage().apply { value = sealedValue() }
        val crypto = Crypto().apply { transientFailures = 1 }
        KeyVault(storage, crypto).save("replacement")
        assertEquals("replacement", String(storage.value!!.ciphertext)); assertEquals(0, crypto.deletes)
        val old = storage.value
        crypto.transientFailures = 2
        try { KeyVault(storage, crypto).save("not-saved"); fail() } catch (_: ProviderException) { }
        assertSame(old, storage.value); assertEquals(0, crypto.deletes); assertEquals(0, crypto.creates)
    }
}
