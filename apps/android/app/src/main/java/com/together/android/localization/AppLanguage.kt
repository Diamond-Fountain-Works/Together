package com.together.android.localization

import java.util.Locale

/** Local presentation preference; never enters the shared space or signed operation log. */
enum class AppLanguage(val tag: String) {
    CHINESE("zh-CN"),
    ENGLISH("en");

    val locale: Locale get() = Locale.forLanguageTag(tag)

    companion object {
        fun initial(saved: String?, system: Locale): AppLanguage =
            entries.firstOrNull { it.tag == saved }
                ?: if (system.language.equals("zh", ignoreCase = true)) CHINESE else ENGLISH
    }
}
