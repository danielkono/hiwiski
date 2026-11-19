package de.danielkononov.hiwiski.widgets

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.serialization.Serializable

/** Where and as whom the widgets ask the server. */
@Serializable
data class Credentials(val server: String, val token: String)

/**
 * What the widgets hold: the app's settings and pictures, the pictures they fetched
 * themselves, and the session — the device token encrypted with a key of the Android keystore,
 * which never leaves it. The app's own copy of the token lives in its secure storage; the
 * widgets get theirs over the bridge, so neither has to read the other's format.
 *
 * The app writes the settings and its pictures, the widgets write theirs: each key has one
 * writer, and the two never overwrite each other.
 */
class WidgetStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    var config: String?
        get() = prefs.getString(CONFIG, null)
        set(value) = prefs.edit().putOrRemove(CONFIG, value).apply()

    fun appSnapshot(kind: HomeWidgetKind): String? = prefs.getString(APP + kind.key, null)

    fun setAppSnapshot(kind: HomeWidgetKind, json: String?) = prefs.edit().putOrRemove(APP + kind.key, json).apply()

    fun serverSnapshot(kind: HomeWidgetKind): String? = prefs.getString(SERVER + kind.key, null)

    fun setServerSnapshot(kind: HomeWidgetKind, json: String?) =
        prefs.edit().putOrRemove(SERVER + kind.key, json).apply()

    /** The server answered that the widget's list is gone — or hidden, which reads the same. */
    fun gone(kind: HomeWidgetKind): Boolean = prefs.getBoolean(GONE + kind.key, false)

    fun setGone(kind: HomeWidgetKind, gone: Boolean) = prefs.edit().putBoolean(GONE + kind.key, gone).apply()

    /** New settings: what the server said about the old ones no longer applies. */
    fun forgetGone() = prefs.edit().apply { HomeWidgetKind.entries.forEach { remove(GONE + it.key) } }.apply()

    fun credentials(): Credentials? {
        val sealed = prefs.getString(CREDENTIALS, null) ?: return null
        // A key that is gone (the keystore was reset) leaves nothing readable: the widgets then
        // show what they have until the app hands them the session again.
        return runCatching { widgetJson.decodeFromString<Credentials>(Keystore.open(sealed)) }.getOrNull()
    }

    fun setCredentials(credentials: Credentials?) {
        val sealed = credentials?.let { Keystore.seal(widgetJson.encodeToString(Credentials.serializer(), it)) }
        prefs.edit().putOrRemove(CREDENTIALS, sealed).apply()
    }

    /** Everything — after a sign-out nothing of the member stays on the home screen. */
    fun clear() = prefs.edit().clear().apply()

    private fun android.content.SharedPreferences.Editor.putOrRemove(key: String, value: String?) =
        if (value == null) remove(key) else putString(key, value)

    private companion object {
        const val FILE = "hiwiski_home_widgets"
        const val CONFIG = "config"
        const val APP = "snapshot.app."
        const val SERVER = "snapshot.server."
        const val GONE = "gone."
        const val CREDENTIALS = "credentials"
    }
}

/** AES-GCM with a key that lives in the Android keystore and cannot be read out of it. */
private object Keystore {
    private const val PROVIDER = "AndroidKeyStore"
    private const val ALIAS = "hiwiski.home_widgets"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val TAG_BITS = 128
    private const val IV_BYTES = 12

    fun seal(plain: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, key()) }
        val sealed = cipher.iv + cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(sealed, Base64.NO_WRAP)
    }

    fun open(sealed: String): String {
        val bytes = Base64.decode(sealed, Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION).apply {
            init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, bytes, 0, IV_BYTES))
        }
        return String(cipher.doFinal(bytes, IV_BYTES, bytes.size - IV_BYTES), Charsets.UTF_8)
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(PROVIDER).apply { load(null) }
        (store.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER).run {
            init(
                KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build(),
            )
            generateKey()
        }
    }
}
