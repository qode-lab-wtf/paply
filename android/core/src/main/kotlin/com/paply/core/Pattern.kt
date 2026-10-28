package com.paply.core

/** Unicode classes/case enabled for the ported ICU patterns; matcher ranges use UTF-16. */
internal class Pattern(pattern: String, caseInsensitive: Boolean = false) {
    val regex: java.util.regex.Pattern =
        java.util.regex.Pattern.compile(
            pattern,
            java.util.regex.Pattern.UNICODE_CHARACTER_CLASS or
                java.util.regex.Pattern.UNICODE_CASE or
                if (caseInsensitive) java.util.regex.Pattern.CASE_INSENSITIVE else 0,
        )

    fun matches(text: String) = regex.matcher(text).find()

    fun count(text: String): Int {
        val m = regex.matcher(text)
        var n = 0
        while (m.find()) n++
        return n
    }

    fun replacing(text: String, template: String = "") = regex.matcher(text).replaceAll(template)

    fun replacingFirst(text: String, replacement: String = ""): String {
        val m = regex.matcher(text)
        return if (m.find()) text.replaceRange(m.start(), m.end(), replacement) else text
    }

    fun firstGroup(text: String, group: Int = 1): String? {
        val m = regex.matcher(text)
        return if (m.find()) m.group(group) else null
    }
}
