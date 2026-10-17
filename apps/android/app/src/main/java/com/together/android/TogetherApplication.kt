package com.together.android

import android.app.Application
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.together.android.data.TogetherRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class TogetherApplication : Application(), DefaultLifecycleObserver {
    private var openedRepository: TogetherRepository? = null
    val repository: TogetherRepository
        get() =
            openedRepository
                ?: TogetherRepository(this, applicationScope).also { openedRepository = it }

    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super<Application>.onCreate()
        ProcessLifecycleOwner.get().lifecycle.addObserver(this)
    }

    override fun onStart(owner: LifecycleOwner) {
        openedRepository?.foreground(true)
    }

    override fun onStop(owner: LifecycleOwner) {
        openedRepository?.foreground(false)
    }
}
