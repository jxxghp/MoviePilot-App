pluginManagement {
    repositories {
        maven("https://maven.aliyun.com/repository/gradle-plugin")
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        google()
        mavenCentral()
    }
}

rootProject.name = "MoviePilotAndroid"

include(
    ":app",
    ":core-rust-bridge",
    ":design-system",
    ":core-media",
    ":core-medal3d",
    ":core-plugin-host",
    ":widget",
    ":feature:auth",
    ":feature:discover",
    ":feature:media",
    ":feature:subscribe",
    ":feature:download",
    ":feature:library",
    ":feature:dashboard",
    ":feature:automation",
    ":feature:agent",
    ":feature:settings",
)
