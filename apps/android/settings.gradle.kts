pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }
rootProject.name = "TogetherAndroid"
include(":core:protocol", ":core:domain")
if (providers.gradleProperty("together.jvmOnly").orNull != "true") include(":app")
