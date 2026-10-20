plugins { id("com.android.application"); kotlin("android"); id("org.jetbrains.kotlin.plugin.compose"); id("com.google.devtools.ksp") }
val togetherTestBuildType = providers.gradleProperty("together.testBuildType").orElse("debug").get().also {
    require(it in setOf("debug", "nativeQa")) { "Unsupported isolated test build type" }
}
android {
    namespace = "com.together.android"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.together.android"
        minSdk = 28
        targetSdk = 36
        versionCode = 8
        versionName = "0.2.1-phaseC-plans"
        buildConfigField("String", "RELAY_URL", "\"https://together-connection.together-connection-service.workers.dev\"")
        buildConfigField("boolean", "NATIVE_QA", "false")
        manifestPlaceholders["togetherAppLabel"] = "@string/app_name"
        testInstrumentationRunner = if (togetherTestBuildType == "nativeQa")
            "com.together.android.NativeQaTestRunner" else "com.together.android.IsolatedAndroidTestRunner"
        providers.gradleProperty("together.testRelay").orNull?.let { testInstrumentationRunnerArguments["relayURL"] = it }
    }
    buildTypes {
        debug { applicationIdSuffix = ".debug" }
        create("nativeQa") {
            initWith(getByName("debug"))
            applicationIdSuffix = ".qa.native"
            versionNameSuffix = "-native-qa"
            matchingFallbacks += "debug"
            buildConfigField("boolean", "NATIVE_QA", "true")
            // This independent QA application must never fall back to the production Relay.
            buildConfigField("String", "RELAY_URL", "\"\"")
            manifestPlaceholders["togetherAppLabel"] = "@string/app_name_native_qa"
        }
        release { isMinifyEnabled = true; proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro") }
    }
    buildFeatures { compose = true; buildConfig = true }
    testBuildType = togetherTestBuildType
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
    // Optional native P2P QA only. The shipped application remains on C1.
    androidTestImplementation("computer.iroh:iroh-android:1.1.0")
    "nativeQaImplementation"("computer.iroh:iroh-android:1.1.0")
    androidTestImplementation(platform("androidx.compose:compose-bom:2025.10.01"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

androidComponents {
    onVariants(selector().withBuildType("nativeQa")) { variant ->
        variant.outputs.forEach { output ->
            output.versionCode.set(12)
            output.versionName.set("0.2.1-native-app-qa")
        }
    }
}
