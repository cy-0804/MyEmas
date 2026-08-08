allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                val getNamespaceMethod = androidExt.javaClass.getMethod("getNamespace")
                val namespace = getNamespaceMethod.invoke(androidExt)
                if (namespace == null) {
                    val setNamespaceMethod = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                    setNamespaceMethod.invoke(androidExt, project.group.toString())
                }
            } catch (e: Exception) {
                // ignore if method doesn't exist
            }

            // Force all plugins to compile against SDK 36
            try {
                val setCompileSdk = androidExt.javaClass.getMethod("setCompileSdkVersion", Int::class.java)
                setCompileSdk.invoke(androidExt, 36)
            } catch (e: Exception) {
                // ignore if not applicable
            }

            // Force all Android modules to use at least minSdk 21
            try {
                val getDefaultConfigMethod = androidExt.javaClass.getMethod("getDefaultConfig")
                val defaultConfig = getDefaultConfigMethod.invoke(androidExt)
                val setMinSdkMethod = defaultConfig.javaClass.getMethod("setMinSdkVersion", Integer::class.java)
                setMinSdkMethod.invoke(defaultConfig, 21)
            } catch (e: Exception) {
                // ignore if not applicable
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
    
    // Fix for "different roots" crash on Windows across drives
    project.tasks.configureEach {
        if (name.contains("generateDebugUnitTestConfig") || name.contains("generateReleaseUnitTestConfig")) {
            enabled = false
        }
    }
}



tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
