// Top-level build file (android/build.gradle.kts)
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // ADD THIS LINE FOR FIREBASE
        classpath("com.google.gms:google-services:4.4.2")
        // If you use Kotlin Gradle plugin (already there usually)
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.24")
        // Other classpaths Flutter adds automatically...
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Rest of your code (custom build dir, clean task, etc.)
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}