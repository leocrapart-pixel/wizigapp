plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "dev.wizig.wizigapp"
    compileSdk = 36
    ndkVersion = "27.3.13750724"

    defaultConfig {
        applicationId = "dev.wizig.wizigapp"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            // Devices we actually ship: 64-bit phones (arm64) and the emulator (x86_64).
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    buildFeatures {
        compose = true
    }

    externalNativeBuild {
        cmake {
            path = rootProject.file("../.wizig/generated/android/jni/CMakeLists.txt")
        }
    }

    sourceSets {
        getByName("main") {
            kotlin.directories.add(rootProject.file("../.wizig/sdk/android/src/main/kotlin").path)
            jniLibs.directories.add(rootProject.file("../.wizig/generated/android/jniLibs").path)
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

kotlin {
    jvmToolchain(21)
}

val wizigAbiTargets: Map<String, String> = mapOf(
    "arm64-v8a" to "aarch64-linux-android",
    "x86_64" to "x86_64-linux-android",
)

val requestedWizigAbi: String? = providers.gradleProperty("wizig.ffi.abi").orNull
if (requestedWizigAbi != null && requestedWizigAbi !in wizigAbiTargets.keys) {
    throw org.gradle.api.GradleException(
        "Unsupported Wizig FFI ABI '${requestedWizigAbi}'. Supported values: ${wizigAbiTargets.keys.joinToString(", ")}"
    )
}

val supportedWizigOptimizeModes: Set<String> = setOf("Debug", "ReleaseFast", "ReleaseSafe", "ReleaseSmall")

val requestedWizigOptimize: String = providers.gradleProperty("wizig.ffi.optimize").orNull ?: "Debug"
if (requestedWizigOptimize !in supportedWizigOptimizeModes) {
    throw org.gradle.api.GradleException(
        "Unsupported Wizig FFI optimize mode '${requestedWizigOptimize}'. Supported values: ${supportedWizigOptimizeModes.joinToString(", ")}"
    )
}

fun discoverWizigZigBinary(): String {
    val explicit = providers.gradleProperty("wizig.zig.bin").orNull ?: System.getenv("ZIG_BINARY")
    if (!explicit.isNullOrBlank()) return explicit

    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.isFile) {
        val fromLocalProperties = runCatching {
            localPropertiesFile.readLines()
                .asSequence()
                .map { line -> line.trim() }
                .firstOrNull { line -> line.startsWith("wizig.zig.bin=") }
                ?.substringAfter("=")
                ?.trim()
        }.getOrNull()
        if (!fromLocalProperties.isNullOrBlank()) return fromLocalProperties
    }

    val pathProbe = runCatching {
        val process = ProcessBuilder("which", "zig").redirectErrorStream(true).start()
        val output = process.inputStream.bufferedReader().readText().trim()
        if (process.waitFor() == 0 && output.isNotEmpty()) output else null
    }.getOrNull()
    if (!pathProbe.isNullOrBlank()) return pathProbe

    val home = System.getProperty("user.home") ?: ""
    val candidates = listOf(
        "$home/.zvm/master/zig",
        "$home/.zvm/bin/zig",
        "$home/.local/bin/zig",
        "/opt/homebrew/bin/zig",
        "/usr/local/bin/zig",
    )
    for (candidate in candidates) {
        if (rootProject.file(candidate).canExecute()) return candidate
    }

    throw org.gradle.api.GradleException(
        "zig is not installed or discoverable (PATH/wizig.zig.bin/ZIG_BINARY/common locations)"
    )
}

fun abiTaskSuffix(abi: String): String =
    abi.split('-', '_').joinToString("") { segment ->
        segment.replaceFirstChar { ch ->
            if (ch.isLowerCase()) ch.titlecase() else ch.toString()
        }
    }

fun registerWizigFfiTask(abi: String, zigTarget: String) =
    tasks.register<Exec>("buildWizigFfi${abiTaskSuffix(abi)}") {
        val appRoot = rootProject.file("..")
        val outDir = appRoot.resolve(".wizig/generated/android/jniLibs/$abi")
        val outFile = outDir.resolve("libwizigffi.so")
        val generatedRoot = appRoot.resolve(".wizig/generated/zig")
        val runtimeRoot = appRoot.resolve(".wizig/runtime")
        val libRoot = appRoot.resolve("lib")

        group = "wizig"
        description = "Build Wizig FFI for Android ABI $abi"

        inputs.file(generatedRoot.resolve("WizigGeneratedFfiRoot.zig"))
        inputs.file(runtimeRoot.resolve("core/root.zig"))
        inputs.file(libRoot.resolve("WizigGeneratedAppModule.zig"))
        inputs.property("abi", abi)
        inputs.property("zigTarget", zigTarget)
        outputs.file(outFile)

        onlyIf { requestedWizigAbi == null || requestedWizigAbi == abi }

        doFirst {
            outDir.mkdirs()
        }

        commandLine(
            discoverWizigZigBinary(),
            "build-lib",
            "-O${requestedWizigOptimize}",
            "-target",
            zigTarget,
            "--dep",
            "wizig_core",
            "--dep",
            "wizig_app",
            "-Mroot=${generatedRoot.path}/WizigGeneratedFfiRoot.zig",
            "-Mwizig_core=${runtimeRoot.path}/core/root.zig",
            "-Mwizig_app=${libRoot.path}/WizigGeneratedAppModule.zig",
            "--name",
            "wizigffi",
            "-dynamic",
            "-femit-bin=${outFile.path}",
        )
    }

val buildWizigFfiTasks = wizigAbiTargets.map { (abi, zigTarget) ->
    registerWizigFfiTask(abi, zigTarget)
}

tasks.register("buildWizigFfi") {
    group = "wizig"
    description = "Build Wizig FFI shared libraries for required Android ABI targets"
    dependsOn(buildWizigFfiTasks)
}

tasks.matching { it.name.startsWith("configureCMake") || it.name.startsWith("buildCMake") }.configureEach {
    dependsOn("buildWizigFfi")
}

tasks.matching { it.name.startsWith("merge") && it.name.endsWith("JniLibFolders") }.configureEach {
    dependsOn("buildWizigFfi")
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation("net.java.dev.jna:jna:5.14.0")

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)

    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
