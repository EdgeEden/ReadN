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
    project.evaluationDependsOn(":app")
}

subprojects {
    if (project.name != "app") {
        val configureCompileSdk = {
            val android = project.extensions.findByName("android")
            if (android != null) {
                for (m in android.javaClass.methods) {
                    if (m.name == "compileSdkVersion" && m.parameterTypes.size == 1 &&
                        (m.parameterTypes[0] == Int::class.javaPrimitiveType || m.parameterTypes[0] == java.lang.Integer::class.java)) {
                        try { m.invoke(android, 36) } catch (_: Throwable) {}
                        break
                    } else if (m.name == "setCompileSdk" && m.parameterTypes.size == 1 &&
                        (m.parameterTypes[0] == Int::class.javaPrimitiveType || m.parameterTypes[0] == java.lang.Integer::class.java)) {
                        try { m.invoke(android, 36) } catch (_: Throwable) {}
                        break
                    }
                }
            }
        }
        if (project.state.executed) {
            configureCompileSdk()
        } else {
            afterEvaluate {
                configureCompileSdk()
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

