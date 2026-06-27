package com.mediamix.desktop

import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import androidx.compose.ui.unit.dp
import org.koin.core.context.startKoin
import com.mediamix.shared.di.sharedModule
import com.mediamix.ui.di.uiModule
import com.mediamix.ui.App
import com.mediamix.ui.theme.MediaMixTheme
import com.mediamix.ui.theme.ThemeConfig
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue

fun main() {
    startKoin {
        modules(sharedModule, uiModule)
    }
    application {
        Window(
            onCloseRequest = ::exitApplication,
            title = "MediaMix",
            state = rememberWindowState(width = 1280.dp, height = 800.dp)
        ) {
            val themeMode by ThemeConfig.themeMode.collectAsState()
            MediaMixTheme(themeMode = themeMode) {
                App()
            }
        }
    }
}
