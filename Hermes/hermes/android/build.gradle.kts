allprojects {
    repositories {
        google()
        mavenCentral()
        // vosk-android aar (Türkçe ASR de-risk) — alphacephei maven.
        maven { url = uri("https://alphacephei.com/maven/") }
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

// vosk_flutter_2 1.0.5 (Türkçe ASR de-risk) eski AGP'ye göre yazılmış: manifest'te
// `package` var ama build.gradle'da `namespace` yok → AGP 8 build'i patlatıyor.
// Eksik namespace'i reflection ile enjekte ediyoruz (root script'te AGP tipi import
// gerektirmesin diye). Sadece bu pakete dokunur. Vosk benimsenmezse bu blok da silinir.
subprojects {
    if (project.name == "vosk_flutter_2") {
        afterEvaluate {
            extensions.findByName("android")?.let { ext ->
                val getNamespace = ext.javaClass.getMethod("getNamespace")
                if (getNamespace.invoke(ext) == null) {
                    ext.javaClass
                        .getMethod("setNamespace", String::class.java)
                        .invoke(ext, "org.vosk.vosk_flutter")
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
