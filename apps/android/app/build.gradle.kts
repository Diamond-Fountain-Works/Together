import java.util.Properties
import java.security.MessageDigest
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.ZipFile
import groovy.json.JsonSlurper

plugins { id("com.android.application"); kotlin("android"); id("org.jetbrains.kotlin.plugin.compose"); id("com.google.devtools.ksp") }
val togetherTestBuildType = providers.gradleProperty("together.testBuildType").orElse("debug").get().also {
    require(it in setOf("debug", "nativeQa")) { "Unsupported isolated test build type" }
}
// Release credentials live outside the repository. Never fall back to the Debug key.
val releaseSigning = Properties().apply {
    providers.gradleProperty("together.signingProperties").orNull?.let { path ->
        val source = file(path)
        require(source.isFile) { "Release signing properties file is unavailable" }
        source.inputStream().use(::load)
    }
}
fun signingValue(key: String, environment: String): String? =
    providers.environmentVariable(environment).orNull ?: releaseSigning.getProperty(key)
val releaseKeyStore = signingValue("storeFile", "TOGETHER_ANDROID_KEYSTORE")
val releaseStorePassword = signingValue("storePassword", "TOGETHER_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "TOGETHER_ANDROID_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "TOGETHER_ANDROID_KEY_PASSWORD")
val hasReleaseSigning = listOf(releaseKeyStore, releaseStorePassword, releaseKeyAlias, releaseKeyPassword)
    .all { !it.isNullOrBlank() }
// Optional reproducible v1.1.0 rebuild: same Kotlin classes, corrected Android ELF link alignment.
val nativeReleaseAar = providers.gradleProperty("together.nativeReleaseAar").orNull?.let(::file)
val nativeReleaseAarDigest = providers.gradleProperty("together.nativeReleaseAarSha256").orNull
val nativeReleaseReceipt = providers.gradleProperty("together.nativeReleaseManifest").orNull?.let(::file)
    ?: nativeReleaseAar?.resolveSibling(nativeReleaseAar.name.removeSuffix(".aar") + ".json")
if (nativeReleaseAar != null) {
    require(nativeReleaseAar.isFile && nativeReleaseAarDigest?.matches(Regex("[0-9a-f]{64}")) == true) {
        "A native Release AAR requires its existing file and exact SHA-256"
    }
    val actual = nativeReleaseAar.inputStream().use { input ->
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(65_536)
        while (true) { val size = input.read(buffer); if (size < 0) break; digest.update(buffer, 0, size) }
        digest.digest().joinToString("") { "%02x".format(it) }
    }
    require(actual == nativeReleaseAarDigest) { "Native Release AAR SHA-256 mismatch" }
}
android {
    namespace = "com.together.android"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.together.android"
        minSdk = 28
        targetSdk = 36
        versionCode = 15
        versionName = "0.2.2"
        buildConfigField("String", "RELAY_URL", "\"https://together-connection.together-connection-service.workers.dev\"")
        buildConfigField("boolean", "NATIVE_QA", "false")
        buildConfigField("boolean", "NATIVE_P2P", "false")
        manifestPlaceholders["togetherAppLabel"] = "@string/app_name"
        testInstrumentationRunner = if (togetherTestBuildType == "nativeQa")
            "com.together.android.NativeQaTestRunner" else "com.together.android.IsolatedAndroidTestRunner"
        providers.gradleProperty("together.testRelay").orNull?.let { testInstrumentationRunnerArguments["relayURL"] = it }
    }
    signingConfigs {
        if (hasReleaseSigning) create("release") {
            storeFile = file(releaseKeyStore!!)
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }
    buildTypes {
        debug { applicationIdSuffix = ".debug" }
        create("nativeQa") {
            initWith(getByName("debug"))
            applicationIdSuffix = ".qa.native"
            versionNameSuffix = "-native-qa"
            matchingFallbacks += "debug"
            buildConfigField("boolean", "NATIVE_QA", "true")
            buildConfigField("boolean", "NATIVE_P2P", "true")
            // This independent QA application must never fall back to the production Relay.
            buildConfigField("String", "RELAY_URL", "\"\"")
            manifestPlaceholders["togetherAppLabel"] = "@string/app_name_native_qa"
        }
        release {
            isMinifyEnabled = true
            isDebuggable = false
            buildConfigField("boolean", "NATIVE_P2P", "true")
            buildConfigField("String", "RELAY_URL", "\"\"")
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("release")
            // This release supports Android arm64 phones; other ABIs require their own rebuilt ELF.
            ndk { abiFilters += "arm64-v8a" }
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    buildFeatures { compose = true; buildConfig = true }
    testBuildType = togetherTestBuildType
    sourceSets.getByName("nativeQa").java.srcDir("src/native/java")
    sourceSets.getByName("release").java.srcDir("src/native/java")
    if (togetherTestBuildType == "nativeQa") {
        sourceSets.getByName("androidTest").apply {
            java.setSrcDirs(listOf("src/nativeQaAndroidTest/java"))
            manifest.srcFile("src/nativeQaAndroidTest/AndroidManifest.xml")
        }
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    packaging { resources.excludes += setOf("META-INF/versions/9/OSGI-INF/MANIFEST.MF", "META-INF/LICENSE*", "META-INF/NOTICE*") }
}
ksp { arg("room.schemaLocation", "$projectDir/schemas") }
dependencies {
    implementation(project(":core:domain"))
    implementation(platform("androidx.compose:compose-bom:2025.10.01"))
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-process:2.9.4")
    implementation("androidx.room:room-runtime:2.8.4")
    implementation("androidx.room:room-ktx:2.8.4")
    ksp("androidx.room:room-compiler:2.8.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation(testFixtures(project(":core:protocol")))
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.7.0")
    // Debug retains legacy C1; Release and isolated native QA reuse one native adapter.
    androidTestImplementation("computer.iroh:iroh-android:1.1.0")
    "nativeQaImplementation"("computer.iroh:iroh-android:1.1.0")
    if (nativeReleaseAar != null) {
        "releaseImplementation"(files(nativeReleaseAar))
        // The original AAR declares this dependency; a local AAR has no Maven POM.
        "releaseImplementation"("computer.iroh:iroh:1.1.0") {
            exclude(group = "net.java.dev.jna", module = "jna")
        }
        "releaseImplementation"("net.java.dev.jna:jna:5.15.0@aar") { isTransitive = false }
    } else "releaseImplementation"("computer.iroh:iroh-android:1.1.0")
    androidTestImplementation(platform("androidx.compose:compose-bom:2025.10.01"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}

val validateReleaseSigning by tasks.registering {
    doLast {
        check(hasReleaseSigning) {
            "Release signing is required: configure together.signingProperties or TOGETHER_ANDROID_KEYSTORE credentials; Debug signing is never used"
        }
        check(file(releaseKeyStore!!).isFile) { "Release keystore is unavailable" }
    }
}

val validateReleaseNativeArtifact by tasks.registering {
    doLast {
        check(nativeReleaseAar != null) {
            "Release packaging is blocked: supply the security-patched arm64 16 KiB AAR, exact SHA-256 and source receipt"
        }
        // This checks reproducible build provenance, not independent protocol/security approval.
        val trustedManifestFile = rootProject.file("../../packages/together-native-source/source-manifest.json")
        val trustedLockFile = rootProject.file("../../packages/together-native-source/Cargo.lock")
        val trusted = JsonSlurper().parse(trustedManifestFile) as Map<*, *>
        fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        check(trusted["schemaVersion"] == 1 && trusted["protocolChanges"] == false &&
            trusted["ffiWrapperSourceChanges"] == false &&
            trusted["sourceChanges"] == listOf("Cargo.lock") &&
            trusted["secureCargoLockSHA256"] == digest(trustedLockFile.readBytes())) {
            "Tracked native security source manifest/lock is inconsistent"
        }
        val versions = trusted["dependencyVersions"] as? Map<*, *> ?: error("Missing trusted dependency versions")
        check(listOf("iroh", "iroh-base", "iroh-relay", "iroh-dns").all { versions[it] == "1.1.0" }) {
            "Native source must include the reviewed Iroh 1.1.0 advisory fixes"
        }
        check(nativeReleaseReceipt?.isFile == true) { "Native Release build source receipt is unavailable" }
        val receipt = JsonSlurper().parse(nativeReleaseReceipt) as Map<*, *>
        check(receipt["status"] == "PASS" && receipt["sourceRepository"] == trusted["sourceRepository"] &&
            receipt["sourceCommit"] == trusted["sourceCommit"] &&
            receipt["sourceManifestSHA256"] == digest(trustedManifestFile.readBytes()) &&
            receipt["secureCargoLockSHA256"] == trusted["secureCargoLockSHA256"] &&
            receipt["dependencyVersions"] == versions && receipt["sourceChanges"] == listOf("Cargo.lock") &&
            receipt["originalAARSHA256"] == trusted["originalAndroidAARSHA256"] &&
            receipt["outputAARSHA256"] == nativeReleaseAarDigest &&
            receipt["classesJarPreserved"] == true && receipt["otherEntriesPreserved"] == true &&
            receipt["ffiExportsEqual"] == true && receipt["rebuiltABI"] == "arm64-v8a") {
            "Native Release receipt does not prove the pinned security source/build; old alignment-only artifacts are rejected"
        }
        ZipFile(nativeReleaseAar).use { archive ->
            val classes = archive.getEntry("classes.jar") ?: error("Native AAR is missing classes.jar")
            val classDigest = archive.getInputStream(classes).use { input ->
                MessageDigest.getInstance("SHA-256").digest(input.readBytes()).joinToString("") { "%02x".format(it) }
            }
            check(classDigest == trusted["classesJarSHA256"] && classDigest == receipt["classesJarSHA256"]) {
                "Native AAR changed the original verified Iroh 1.1.0 Android classes"
            }
            val library = archive.getEntry("jni/arm64-v8a/libiroh_ffi.so") ?: error("Native AAR is missing arm64 ELF")
            val bytes = archive.getInputStream(library).use { it.readBytes() }
            check(digest(bytes) == receipt["arm64LibrarySHA256"]) { "Native ELF differs from its security build receipt" }
            check(bytes.size >= 64 && bytes.copyOfRange(0, 4).contentEquals(byteArrayOf(0x7f, 0x45, 0x4c, 0x46)) &&
                bytes[4].toInt() == 2 && bytes[5].toInt() == 1) { "Native artifact is not a little-endian ELF64" }
            val elf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            check(elf.getShort(18).toInt() == 183) { "Native artifact is not Android arm64" }
            val headersAt = elf.getLong(32)
            val headerSize = elf.getShort(54).toInt() and 0xffff
            val headerCount = elf.getShort(56).toInt() and 0xffff
            check(headerSize >= 56 && headerCount > 0 && headersAt >= 64 &&
                headersAt + headerCount.toLong() * headerSize <= bytes.size) { "Invalid native program headers" }
            var loads = 0
            repeat(headerCount) { index ->
                val at = (headersAt + index.toLong() * headerSize).toInt()
                if (elf.getInt(at) == 1) {
                    loads++
                    val offset = elf.getLong(at + 8)
                    val address = elf.getLong(at + 16)
                    val alignment = elf.getLong(at + 48)
                    check(alignment >= 16_384 && (alignment and (alignment - 1)) == 0L &&
                        offset % alignment == address % alignment && offset % 16_384 == address % 16_384) {
                        "Release packaging is blocked: native LOAD segment is not compatible with 16 KiB pages"
                    }
                }
            }
            check(loads > 0) { "Native artifact has no LOAD segments" }
        }
    }
}
tasks.matching { it.name == "packageRelease" }.configureEach {
    dependsOn(validateReleaseSigning, validateReleaseNativeArtifact)
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.packaging.resources.excludes.addAll("darwin-*/**", "win32-*/**", "linux-*/**")
    }
    onVariants(selector().withBuildType("nativeQa")) { variant ->
        variant.outputs.forEach { output ->
            output.versionCode.set(15)
            output.versionName.set("0.2.2-native-app-qa")
        }
    }
}
