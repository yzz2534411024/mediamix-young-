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
