package com.together.android.localization

import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.content.res.Resources
import android.os.LocaleList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Switching language updates resources without recreating the Activity, repository or sync session. */
class AppLanguageStore(private val context: Context) {
    private val preferences = context.getSharedPreferences("together-presentation", Context.MODE_PRIVATE)
    private val initial = AppLanguage.initial(preferences.getString("language", null),
        Resources.getSystem().configuration.locales[0])
    private val current = MutableStateFlow(initial)
    val language = current.asStateFlow()

    init {
        // Persist the first choice so a later system-language change cannot silently alter the app.
        if (preferences.getString("language", null) != initial.tag)
            preferences.edit().putString("language", initial.tag).apply()
    }

    fun select(value: AppLanguage) {
        if (current.value == value) return
        preferences.edit().putString("language", value.tag).apply()
        current.value = value
    }

    fun localizedContext(base: Context, value: AppLanguage = current.value): Context {
        val configuration = Configuration(base.resources.configuration)
        configuration.setLocales(LocaleList(value.locale))
        val localized = base.createConfigurationContext(configuration)
        // Retain the Activity in the ContextWrapper chain for document/permission launchers.
        return object : ContextWrapper(base) {
            override fun getResources(): Resources = localized.resources
            override fun getAssets() = localized.assets
        }
    }

    /** Long-lived repositories resolve the currently selected locale on every resource lookup. */
    fun repositoryContext(): Context = object : ContextWrapper(context) {
        override fun getResources(): Resources = localizedContext(context).resources
    }
}
