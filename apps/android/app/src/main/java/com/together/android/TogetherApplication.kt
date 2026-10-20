package com.together.android

import android.app.Application
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.lifecycle.Lifecycle
import com.together.android.data.TogetherRepository
import com.together.protocol.requireProtocol
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class TogetherApplication : Application(), DefaultLifecycleObserver {
    private var openedRepository: TogetherRepository? = null
    val repository: TogetherRepository
        get() =
            openedRepository
                ?: TogetherRepository(this, applicationScope,
                    namespace = if (BuildConfig.NATIVE_QA) "NATIVE-APP" else null).also {
                    openedRepository = it
                    it.foreground(ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED))
                }

    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super<Application>.onCreate()
        requireProtocol(!BuildConfig.NATIVE_QA ||
            (BuildConfig.DEBUG && packageName == "com.together.android.qa.native" && BuildConfig.RELAY_URL.isEmpty()),
            "ISOLATED_NATIVE_QA_REQUIRED")
        ProcessLifecycleOwner.get().lifecycle.addObserver(this)
    }

    override fun onStart(owner: LifecycleOwner) {
        openedRepository?.foreground(true)
    }

    override fun onStop(owner: LifecycleOwner) {
        openedRepository?.foreground(false)
    }
}
