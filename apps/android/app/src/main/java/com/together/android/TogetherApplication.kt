package com.together.android

import android.app.Application
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.lifecycle.Lifecycle
import com.together.android.data.TogetherRepository
import com.together.android.data.NativeRuntimePolicy
import com.together.android.localization.AppLanguageStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class TogetherApplication : Application(), DefaultLifecycleObserver {
    val languages: AppLanguageStore by lazy { AppLanguageStore(this) }
    private var openedRepository: TogetherRepository? = null
    val repository: TogetherRepository
        get() =
            openedRepository
                ?: TogetherRepository(languages.repositoryContext(), applicationScope,
                    namespace = if (BuildConfig.NATIVE_QA) "NATIVE-APP" else null).also {
                    openedRepository = it
                    it.foreground(ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED))
                }

    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super<Application>.onCreate()
        NativeRuntimePolicy.validate(BuildConfig.NATIVE_P2P, BuildConfig.NATIVE_QA, BuildConfig.DEBUG,
            packageName, if (BuildConfig.NATIVE_QA) "NATIVE-APP" else null, BuildConfig.RELAY_URL)
        ProcessLifecycleOwner.get().lifecycle.addObserver(this)
    }

    override fun onStart(owner: LifecycleOwner) {
        openedRepository?.foreground(true)
    }

    override fun onStop(owner: LifecycleOwner) {
        openedRepository?.foreground(false)
    }
}
