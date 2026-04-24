plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

/**
 * Derives versionName from `git describe --tags --dirty`.
 * Strips a leading "v" so tags like v0.9.0 become 0.9.0.
 * Falls back to the supplied default when git is unavailable, the project
 * isn't a git repo, or no tag is reachable from HEAD.
 */
fun gitVersionName(fallback: String): String {
    return try {
        val exec = providers.exec {
            commandLine("git", "describe", "--tags", "--dirty=-dirty")
            isIgnoreExitValue = true
        }
        val exitCode = exec.result.get().exitValue
        val output = exec.standardOutput.asText.get().trim()
        if (exitCode == 0 && output.isNotEmpty()) output.removePrefix("v") else fallback
    } catch (_: Exception) {
        fallback
    }
}

android {
    namespace = "io.github.pstanar.pstotp"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.github.pstanar.pstotp"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = gitVersionName(fallback = "1.0.0")
    }

    signingConfigs {
        // Pin the debug keystore to a repo-committed file so every build —
        // host or container, yours or mine — produces an APK with the same
        // signing identity. Without this, AGP auto-generates a random
        // keystore per machine, which breaks Android passkey binding
        // (assetlinks.json fingerprint goes stale on every rebuild) and
        // blocks APK-over-APK upgrades. The password / alias are the
        // standard Android Studio debug defaults — this key is public on
        // purpose, same posture Google takes with its own debug keystore.
        getByName("debug") {
            storeFile = file("${rootDir}/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    buildFeatures {
        compose = true
    }
}

/**
 * Print signing certificate fingerprints for WebAuthn/passkey Digital Asset Links setup.
 *
 * Usage: ./gradlew :app:passkeyConfig
 *
 * Outputs the appsettings.json snippet to configure the server for Android passkeys.
 */
run {
    data class SigningInfo(val name: String, val storePath: String, val alias: String, val storePass: String)
    val signingInfos = mutableListOf<SigningInfo>()
    val appNamespace = android.namespace ?: "io.github.pstanar.pstotp"

    afterEvaluate {
        android.signingConfigs.forEach { config ->
            val storeFile = config.storeFile ?: return@forEach
            if (!storeFile.exists()) return@forEach
            signingInfos.add(SigningInfo(
                name = config.name,
                storePath = storeFile.absolutePath,
                alias = config.keyAlias ?: "androiddebugkey",
                storePass = config.storePassword ?: "android",
            ))
        }
    }

    tasks.register("passkeyConfig") {
        group = "verification"
        description = "Print signing cert hash for WebAuthn Digital Asset Links config"
        notCompatibleWithConfigurationCache("Reads signing configs at execution time")
        doLast {
            signingInfos.forEach { info ->
                val proc = ProcessBuilder(
                    "keytool", "-list", "-v",
                    "-keystore", info.storePath,
                    "-alias", info.alias,
                    "-storepass", info.storePass,
                ).redirectErrorStream(true).start()

                val output = proc.inputStream.bufferedReader().readText()
                proc.waitFor()

                val sha256Line = output.lines().firstOrNull { it.trim().startsWith("SHA256:") }
                if (sha256Line != null) {
                    val hexFingerprint = sha256Line.substringAfter("SHA256:").trim()

                    println()
                    println("=== Passkey Config for signing config '${info.name}' ===")
                    println()
                    println("SHA-256 fingerprint: $hexFingerprint")
                    println()
                    println("Add to server appsettings.json:")
                    println("""  "Android": {""")
                    println("""    "PackageName": "$appNamespace",""")
                    println("""    "CertFingerprints": [ "$hexFingerprint" ]""")
                    println("""  }""")
                    println()
                    println("The server will auto-generate /.well-known/assetlinks.json")
                    println("and auto-add the android:apk-key-hash origin to Fido2.")
                    println()
                }
            }
        }
    }
}

dependencies {
    implementation(project(":core"))

    // Compose
    implementation(platform("androidx.compose:compose-bom:2025.04.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.activity:activity-compose:1.10.1")
    debugImplementation("androidx.compose.ui:ui-tooling")

    // Navigation
    implementation("androidx.navigation:navigation-compose:2.9.0")

    // Lifecycle
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.0")
    implementation("androidx.lifecycle:lifecycle-process:2.9.0")

    // QR scanning (ML Kit + CameraX)
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
    implementation("androidx.camera:camera-camera2:1.5.0")
    implementation("androidx.camera:camera-lifecycle:1.5.0")
    implementation("androidx.camera:camera-view:1.5.0")

    // Drag-to-reorder
    implementation("sh.calvin.reorderable:reorderable:2.4.3")

    // QR code generation
    implementation("com.google.zxing:core:3.5.3")

    // Biometric
    implementation("androidx.biometric:biometric:1.4.0-alpha04")

    // Credential Manager (WebAuthn/passkey)
    implementation("androidx.credentials:credentials:1.5.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.5.0")

    // Core Android
    implementation("androidx.core:core-ktx:1.16.0")
}
