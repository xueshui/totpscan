package com.scanauth.sdk.internal

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.scanauth.sdk.AccountType
import com.scanauth.sdk.SdkError
import com.scanauth.sdk.SdkException
import com.scanauth.sdk.TotpAlgorithm
import com.scanauth.sdk.TotpParameters
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import java.security.MessageDigest
import java.util.Locale

/** 固化在本地安全存储中的单个账户记录。 */
internal data class AccountRecord(
    /** 本地唯一标识（不可猜测但非敏感）。 */
    val localId: String,
    val type: AccountType,
    /** 账号标识（来自二维码 `acc` 或 otpauth label）。 */
    val accountId: String,
    /** 用户填写的本地备注（仅本机存储）。 */
    val remark: String,
    val issuer: String,
    /** 仅协议账户：规范化后的提交地址（写入后不可变，只能重新绑定）。 */
    val submitUrlCanonical: String?,
    /** Base32 编码的 TOTP 共享密钥。 */
    val secretBase32: String,
    val boundAtEpochMs: Long,
    /** 服务端绑定标识（仅协议账户）。 */
    val bindingId: String,
    /** 服务端确认时间（Unix 毫秒）；0 表示尚未确认（仅协议账户可能为 0）。 */
    val confirmedAtEpochMs: Long,
    val algorithm: TotpAlgorithm,
    val digits: Int,
    val periodSeconds: Long,
    /** 仅协议账户：绑定钉住的注册域名（PSL 子集推导）。 */
    val registeredDomain: String = "",
    /** 仅协议账户：绑定钉住的 `path[?query]`。 */
    val submitPath: String = ""
) {
    val parameters: TotpParameters
        get() = TotpParameters(algorithm, digits, periodSeconds)

    val isConfirmed: Boolean
        get() = type == AccountType.STANDARD || confirmedAtEpochMs > 0

    /** 展示名：备注优先，否则 `issuer · accountId`。 */
    val displayName: String
        get() = remark.ifBlank {
            if (issuer.isBlank()) accountId else "$issuer · $accountId"
        }

    companion object {
        fun newLocalId(
            type: AccountType,
            accountId: String,
            issuer: String,
            submitUrlCanonical: String?
        ): String {
            val material = "${type.name}\n$issuer\n$accountId\n${submitUrlCanonical.orEmpty()}"
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(material.toByteArray(Charsets.UTF_8))
            val builder = StringBuilder(16)
            for (index in 0 until 8) {
                builder.append(String.format(Locale.ROOT, "%02x", digest[index]))
            }
            return builder.toString()
        }
    }
}

/**
 * 账户数据的安全存储。
 *
 * 实现要点（S3 / §10(2)）：
 * - 使用 Android Keystore 中的 AES-256-GCM 主密钥（密钥材料不可导出）；
 * - 使用 [EncryptedSharedPreferences]（键 AES-256-SIV、值 AES-256-GCM）；
 * - 账户列表整体作为一个加密值存储，避免部分字段明文暴露；
 * - 删除全部账户时清空键值并删除 Keystore 主密钥，残留密文无法再解密。
 */
internal class SecureStore(private val context: Context) {

    companion object {
        private const val PREFS_NAME = "scan_totp_sdk_secure_store"
        private const val MASTER_KEY_ALIAS = "scan_totp_sdk_master_key"

        private const val KEY_ACCOUNTS = "accounts_v3"

        private const val FIELD_ID = "id"
        private const val FIELD_TYPE = "type"
        private const val FIELD_ACCOUNT = "account"
        private const val FIELD_REMARK = "remark"
        private const val FIELD_ISSUER = "issuer"
        private const val FIELD_URL = "url"
        private const val FIELD_SECRET = "secret"
        private const val FIELD_BOUND_AT = "boundAt"
        private const val FIELD_BINDING = "binding"
        private const val FIELD_CONFIRMED_AT = "confirmedAt"
        private const val FIELD_ALGORITHM = "alg"
        private const val FIELD_DIGITS = "digits"
        private const val FIELD_PERIOD = "period"
        private const val FIELD_REGISTERED_DOMAIN = "registeredDomain"
        private const val FIELD_SUBMIT_PATH = "submitPath"
    }

    @Volatile
    private var cached: SharedPreferences? = null

    @Synchronized
    fun loadAll(): List<AccountRecord> {
        val raw = try {
            prefs().getString(KEY_ACCOUNTS, null)
        } catch (e: Exception) {
            throw SdkException(SdkError.SECURE_STORAGE_ERROR, "读取安全存储失败", e)
        } ?: return emptyList()

        return try {
            val array = JSONArray(raw)
            val list = ArrayList<AccountRecord>(array.length())
            for (index in 0 until array.length()) {
                val obj = array.getJSONObject(index)
                list.add(
                    AccountRecord(
                        localId = obj.getString(FIELD_ID),
                        type = if (obj.optString(FIELD_TYPE) == AccountType.STANDARD.name) {
                            AccountType.STANDARD
                        } else {
                            AccountType.PROTOCOL
                        },
                        accountId = obj.getString(FIELD_ACCOUNT),
                        remark = obj.optString(FIELD_REMARK, ""),
                        issuer = obj.optString(FIELD_ISSUER, ""),
                        submitUrlCanonical = obj.optString(FIELD_URL, "").ifBlank { null },
                        secretBase32 = obj.getString(FIELD_SECRET),
                        boundAtEpochMs = obj.optLong(FIELD_BOUND_AT, 0L),
                        bindingId = obj.optString(FIELD_BINDING, ""),
                        confirmedAtEpochMs = obj.optLong(FIELD_CONFIRMED_AT, 0L),
                        algorithm = runCatching {
                            TotpAlgorithm.valueOf(obj.optString(FIELD_ALGORITHM, "SHA1"))
                        }.getOrDefault(TotpAlgorithm.SHA1),
                        digits = obj.optInt(FIELD_DIGITS, 6),
                        periodSeconds = obj.optLong(FIELD_PERIOD, 30L),
                        registeredDomain = obj.optString(FIELD_REGISTERED_DOMAIN, ""),
                        submitPath = obj.optString(FIELD_SUBMIT_PATH, "")
                    )
                )
            }
            list
        } catch (e: Exception) {
            throw SdkException(SdkError.SECURE_STORAGE_ERROR, "账户数据已损坏", e)
        }
    }

    @Synchronized
    fun writeAll(records: List<AccountRecord>) {
        val array = JSONArray()
        records.forEach { record ->
            array.put(
                JSONObject()
                    .put(FIELD_ID, record.localId)
                    .put(FIELD_TYPE, record.type.name)
                    .put(FIELD_ACCOUNT, record.accountId)
                    .put(FIELD_REMARK, record.remark)
                    .put(FIELD_ISSUER, record.issuer)
                    .put(FIELD_URL, record.submitUrlCanonical.orEmpty())
                    .put(FIELD_SECRET, record.secretBase32)
                    .put(FIELD_BOUND_AT, record.boundAtEpochMs)
                    .put(FIELD_BINDING, record.bindingId)
                    .put(FIELD_CONFIRMED_AT, record.confirmedAtEpochMs)
                    .put(FIELD_ALGORITHM, record.algorithm.name)
                    .put(FIELD_DIGITS, record.digits)
                    .put(FIELD_PERIOD, record.periodSeconds)
                    .put(FIELD_REGISTERED_DOMAIN, record.registeredDomain)
                    .put(FIELD_SUBMIT_PATH, record.submitPath)
            )
        }
        try {
            if (!prefs().edit().putString(KEY_ACCOUNTS, array.toString()).commit()) {
                throw SdkException(SdkError.SECURE_STORAGE_ERROR, "写入安全存储失败")
            }
        } catch (e: SdkException) {
            throw e
        } catch (e: Exception) {
            throw SdkException(SdkError.SECURE_STORAGE_ERROR, "写入安全存储失败", e)
        }
    }

    /** 解绑全部账户：清空键值并删除 Keystore 主密钥。 */
    @Synchronized
    fun clearAll() {
        try {
            prefs().edit().clear().commit()
        } catch (e: Exception) {
            SdkLog.w("clear prefs failed")
        }
        cached = null
        try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore")
            keyStore.load(null)
            if (keyStore.containsAlias(MASTER_KEY_ALIAS)) {
                keyStore.deleteEntry(MASTER_KEY_ALIAS)
            }
        } catch (e: Exception) {
            SdkLog.w("delete master key failed")
        }
    }

    @Synchronized
    private fun prefs(): SharedPreferences {
        cached?.let { return it }
        return try {
            val masterKey = MasterKey.Builder(context, MASTER_KEY_ALIAS)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            val prefs = EncryptedSharedPreferences.create(
                context,
                PREFS_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
            cached = prefs
            prefs
        } catch (e: Exception) {
            throw SdkException(SdkError.SECURE_STORAGE_ERROR, "安全存储不可用", e)
        }
    }
}
