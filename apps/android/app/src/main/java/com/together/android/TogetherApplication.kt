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
    lateinit var repository: TogetherRepository; private set
    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    override fun onCreate() {
        super<Application>.onCreate(); repository = TogetherRepository(this, applicationScope)
        ProcessLifecycleOwner.get().lifecycle.addObserver(this)
    }
    override fun onStart(owner: LifecycleOwner) { repository.foreground(true) }
    override fun onStop(owner: LifecycleOwner) { repository.foreground(false) }
}
