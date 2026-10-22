package com.together.android

import android.content.Context
import android.content.ContextWrapper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.localization.AppLanguage
import com.together.android.localization.AppLanguageStore
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** No Activity, database, identity or network is opened by these presentation-only checks. */
@RunWith(AndroidJUnit4::class)
class LanguageSwitchTest {
    @Test fun switchingRefreshesUiAndLongLivedContextAndPersistsWithoutChangingIdentityStorage() {
        val target = InstrumentationRegistry.getInstrumentation().targetContext
        assertTrue("Presentation tests require the isolated Debug app", target.packageName.endsWith(".debug"))
        val context = target.createDeviceProtectedStorageContext()
        // Redirect only the preference name into a dedicated test preference file.
        val isolated = object : ContextWrapper(context) {
            override fun getSharedPreferences(name: String, mode: Int) =
                super.getSharedPreferences("language-test-$name", mode)
        }
        val preferences = isolated.getSharedPreferences("together-presentation", Context.MODE_PRIVATE)
        preferences.edit().clear().commit()
        try {
            val store = AppLanguageStore(isolated)
            val repositoryContext = store.repositoryContext()
            store.select(AppLanguage.CHINESE)
            assertEquals("首页", store.localizedContext(target).getString(R.string.nav_home))
            assertEquals("首页", repositoryContext.getString(R.string.nav_home))
            store.select(AppLanguage.ENGLISH)
            assertEquals("Home", store.localizedContext(target).getString(R.string.nav_home))
            assertEquals("Home", repositoryContext.getString(R.string.nav_home))
            assertEquals(AppLanguage.ENGLISH, AppLanguageStore(isolated).language.value)
            assertEquals(target.packageName, repositoryContext.packageName)
            assertEquals(context.noBackupFilesDir, repositoryContext.noBackupFilesDir)
        } finally {
            preferences.edit().clear().commit()
        }
    }
}
