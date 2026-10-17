package com.together.android

import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.runner.Result
import org.junit.runner.notification.RunListener

/** Passive test-only evidence if the OEM runner fails to terminate after all cases finish. */
class RunnerTeardownDiagnostics : RunListener() {
    override fun testRunFinished(result: Result) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val id = InstrumentationRegistry.getArguments().getString("qaRunId") ?: return
        Thread(
                {
                    Thread.sleep(10_000)
                    val stacks =
                        Thread.getAllStackTraces()
                            .entries
                            .sortedBy { it.key.name }
                            .joinToString("\n\n") { (thread, trace) ->
                                "${thread.name} ${thread.state}\n" +
                                    trace.joinToString("\n") { "  $it" }
                            }
                    File(instrumentation.targetContext.filesDir, "phase-c-teardown-$id.txt")
                        .writeText(stacks)
                    android.util.Log.e(
                        "TogetherPhysicalQa",
                        "Runner still alive ten seconds after ${result.runCount} cases; scoped thread dump saved",
                    )
                },
                "Together-QA-teardown-watchdog",
            )
            .apply {
                isDaemon = true
                start()
            }
    }
}
