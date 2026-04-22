plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("com.google.devtools.ksp")
}

android {
    namespace = "io.github.pstanar.pstotp.core"
    compileSdk = 35

    defaultConfig {
        minSdk = 26
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
}

dependencies {
    // Room (local database)
    implementation("androidx.room:room-runtime:2.7.1")
    implementation("androidx.room:room-ktx:2.7.1")
    ksp("androidx.room:room-compiler:2.7.1")

    // Argon2
    implementation("com.lambdapioneer.argon2kt:argon2kt:1.6.0")

    // HTTP client
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Encrypted storage (Keystore-backed)
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // Testing
    testImplementation("junit:junit:4.13.2")
    // Real org.json implementation on the JVM test classpath — Android's
    // stub returns empty strings for everything, which breaks any test that
    // actually parses JSON.
    testImplementation("org.json:json:20231013")
}
