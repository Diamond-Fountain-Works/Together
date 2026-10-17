plugins { kotlin("jvm"); kotlin("plugin.serialization") }
kotlin { jvmToolchain(21); compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
dependencies { api(project(":core:protocol")); testImplementation("junit:junit:4.13.2"); testImplementation(testFixtures(project(":core:protocol"))) }
sourceSets.main { resources.srcDir(rootProject.file("../../packages/together-core-swift/Sources/TogetherCore/Resources")); resources.include("FinanceCurrencies.json") }
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
