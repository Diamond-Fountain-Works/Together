plugins { kotlin("jvm"); kotlin("plugin.serialization"); `java-test-fixtures` }
kotlin { jvmToolchain(21); compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
dependencies {
    api("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("org.bouncycastle:bcprov-jdk18on:1.86")
    testFixturesApi("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
tasks.test { systemProperty("together.fixtures", rootProject.file("../../protocol/fixtures").absolutePath) }

java { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }

tasks.test {
    inputs.dir(rootProject.file("../../protocol/fixtures"))
    outputs.upToDateWhen {
        !providers.environmentVariable("TOGETHER_LOCAL_RELAY_URL").isPresent &&
        !providers.environmentVariable("TOGETHER_ANDROID_RESPONSE_PATH").isPresent &&
        !providers.environmentVariable("TOGETHER_EXPORT_ANDROID_VECTORS").isPresent
    }
}
