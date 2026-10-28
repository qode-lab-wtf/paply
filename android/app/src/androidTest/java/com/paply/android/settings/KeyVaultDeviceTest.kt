package com.paply.android.settings

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.util.UUID
import javax.crypto.KeyGenerator
import org.junit.Assert.*
import org.junit.Test

/** Uses an isolated alias; never touches the app's configured key. No network calls. */
class KeyVaultDeviceTest {
    private class Storage : VaultStorage {
        var value: EncryptedKey? = null
        var old: String? = null
        override fun encrypted() = value
        override fun write(value: EncryptedKey) { this.value = value }
        override fun clear() { value = null }
        override fun legacy() = old
        override fun removeLegacy() { old = null }
    }
    private fun keyStore() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    @Test fun keystoreRoundTripAndRemovalDeleteTheAlias() {
        val alias = "paply.test.${UUID.randomUUID()}"
        val crypto = KeystoreCryptography(alias)
        try {
            val vault = KeyVault(Storage(), crypto)
            vault.save("test-secret")
            assertEquals("test-secret", vault.read())
            assertTrue(keyStore().containsAlias(alias))
            vault.remove()
            assertNull(vault.read()); assertFalse(keyStore().containsAlias(alias))
        } finally { crypto.deleteKey() }
    }
    @Test fun keyWithoutEncryptionPurposeIsReplacedAndLegacyIsRemoved() {
        val alias = "paply.test.${UUID.randomUUID()}"
        val crypto = KeystoreCryptography(alias)
        try {
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            }.generateKey()
            val storage = Storage().apply { old = "legacy-secret" }
            val vault = KeyVault(storage, crypto)
            assertEquals("legacy-secret", vault.read())
            assertNull(storage.old)
            assertEquals("legacy-secret", vault.read())
        } finally { crypto.deleteKey() }
    }
    @Test fun authenticationFailureRepairsVaultAndAllowsSavingAgain() {
        val alias = "paply.test.${UUID.randomUUID()}"
        val crypto = KeystoreCryptography(alias)
        try {
            val storage = Storage(); val vault = KeyVault(storage, crypto)
            vault.save("test-secret")
            val value = storage.value!!
            storage.value = value.copy(ciphertext = value.ciphertext.copyOf().apply { this[0] = (this[0].toInt() xor 1).toByte() })
            assertNull(vault.read()); assertNull(storage.value)
            vault.save("new-secret"); assertEquals("new-secret", vault.read())
        } finally { crypto.deleteKey() }
    }
}
