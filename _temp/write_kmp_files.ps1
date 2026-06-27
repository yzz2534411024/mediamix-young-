$ErrorActionPreference = "Stop"

# androidApp/build.gradle.kts
$androidBuild = @'
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.compose)
    alias(libs.plugins.compose.compiler)
}

android {
    namespace = "com.mediamix.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.mediamix.app"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    signingConfigs {
        create("debug") {
            // 使用 Android debug keystore（自动）
        }
    }

    buildTypes {
        debug {
            isDebuggable = true
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
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
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation(project(":shared"))
    implementation(project(":composeUi"))
    implementation(libs.activity.compose)
    implementation(libs.media3.exoplayer)
    implementation(libs.media3.exoplayer.hls)
    implementation(libs.media3.exoplayer.dash)
    implementation(libs.media3.ui)
    implementation(libs.compose.material3)
    implementation(libs.compose.runtime)
    implementation(libs.compose.foundation)
    implementation(libs.compose.ui)
    implementation(libs.coil.compose)
    implementation(libs.coil.network.ktor)
    implementation(libs.koin.compose)
}
'@
[System.IO.File]::WriteAllText('e:\mediamix-kmp\androidApp\build.gradle.kts', $androidBuild, [System.Text.Encoding]::UTF8)

# desktopApp/build.gradle.kts
$desktopBuild = @'
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.compose)
    alias(libs.plugins.compose.compiler)
}

kotlin {
    jvm {
        withJava()
        compilations.all {
            kotlinOptions {
                jvmTarget = "17"
            }
        }
    }

    sourceSets {
        val jvmMain by getting {
            dependencies {
                implementation(project(":shared"))
                implementation(project(":composeUi"))
                implementation(libs.compose.material3)
                implementation(libs.compose.runtime)
                implementation(libs.compose.foundation)
                implementation(libs.compose.ui)
                implementation(libs.compose.preview)
                implementation(libs.coil.compose)
                implementation(libs.coil.network.ktor)
                implementation(libs.koin.compose)
                implementation(libs.kotlinx.coroutines.swing)
            }
        }
    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

compose.desktop {
    application {
        mainClass = "com.mediamix.desktop.MainKt"

        nativeDistributions {
            targetFormats(
                org.jetbrains.compose.desktop.application.dsl.TargetFormat.Exe
                // org.jetbrains.compose.desktop.application.dsl.TargetFormat.Msi  // 可选
            )
            packageName = "MediaMix"
            packageVersion = "1.0.0"
            description = "MediaMix - Cross-platform video player"
            copyright = "© 2026 MediaMix. All rights reserved."

            windows {
                menuGroup = "MediaMix"
                upgradeUuid = "515f9605-df43-4595-94d6-aec464c14eec"
                // iconFile.set(project.file("src/main/resources/icon.ico"))  // 图标文件不存在，暂时注释
            }

            // JVM 参数优化
            jvmArgs(
                "-Xmx2g",
                "-Dfile.encoding=UTF-8"
            )
        }
    }
}
'@
[System.IO.File]::WriteAllText('e:\mediamix-kmp\desktopApp\build.gradle.kts', $desktopBuild, [System.Text.Encoding]::UTF8)

# gradle.properties
$gradleProps = @'
# JVM
org.gradle.jvmargs=-Xmx2048M

# 构建优化
org.gradle.parallel=true
org.gradle.caching=true
# org.gradle.configuration-cache=true  # 可能与某些插件不兼容，暂不启用

# Kotlin
kotlin.code.style=official
kotlin.incremental=true
kotlin.incremental.multiplatform=true
kotlin.mpp.androidSourceSetLayoutVersion=2

# Android
android.useAndroidX=true
android.nonTransitiveRClass=true
'@
[System.IO.File]::WriteAllText('e:\mediamix-kmp\gradle.properties', $gradleProps, [System.Text.Encoding]::UTF8)

# proguard-rules.pro
$proguard = @'
# Koin
-keep class org.koin.** { *; }
-keep class com.mediamix.** { *; }

# kotlinx-serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class com.mediamix.**$$serializer { *; }
-keepclassmembers class com.mediamix.** {
    *** Companion;
}
-keepclasseswithmembers class com.mediamix.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Ktor
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**

# SQLDelight
-keep class app.cash.sqldelight.** { *; }

# Coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembernames class kotlinx.** { volatile <fields>; }

# Media3 ExoPlayer
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# General
-keep class * implements java.io.Serializable { *; }
-keepattributes Signature
-keepattributes Exceptions
'@
[System.IO.File]::WriteAllText('e:\mediamix-kmp\androidApp\proguard-rules.pro', $proguard, [System.Text.Encoding]::UTF8)

Write-Host "All 4 files written successfully!"
