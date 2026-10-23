package com.xdl.app

import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/** PBKDF2 is deliberately expensive; run on the dedicated crypto executor. */
internal object NativePrivacyPasswords {
    fun derive(password: String, salt: ByteArray): String {
        require(password.matches(Regex("[0-9]{4,6}")) && salt.size == 16)
        val chars = password.toCharArray()
        val spec = PBEKeySpec(chars, salt, 600000, 256)
        chars.fill('\u0000')
        return try {
            SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                .generateSecret(spec).encoded.joinToString("") { "%02x".format(it.toInt() and 255) }
        } finally {
            spec.clearPassword()
        }
    }
}
