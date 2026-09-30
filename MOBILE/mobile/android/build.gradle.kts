allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// Some geolocator Android plugin releases conditionally skip their namespace
// under the legacy Android DSL. AGP 8 requires one, so set its published package
// namespace as soon as the library plugin is applied.
subprojects {
    plugins.withId("com.android.library") {
        if (name == "geolocator_android") {
            val androidExtension = extensions.findByName("android")
                ?: error("Android extension missing for geolocator_android")
            val setNamespace = androidExtension.javaClass.methods.firstOrNull {
                it.name == "setNamespace" && it.parameterCount == 1
                    && it.parameterTypes[0] == String::class.java
            } ?: error("Android namespace setter missing for geolocator_android")
            setNamespace.invoke(androidExtension, "com.baseflow.geolocator")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
