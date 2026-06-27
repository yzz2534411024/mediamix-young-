package com.mediamix.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.mediamix.ui.App
import com.mediamix.ui.theme.MediaMixTheme
import com.mediamix.ui.theme.ThemeConfig
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val themeMode by ThemeConfig.themeMode.collectAsState()
            MediaMixTheme(themeMode = themeMode) {
                App()
            }
        }
    }
}
