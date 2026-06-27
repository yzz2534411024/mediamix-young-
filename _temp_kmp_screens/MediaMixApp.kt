package com.mediamix.android

import android.app.Application
import org.koin.core.context.startKoin
import com.mediamix.shared.di.sharedModule
import com.mediamix.ui.di.uiModule

class MediaMixApp : Application() {
    override fun onCreate() {
        super.onCreate()
        startKoin {
            modules(sharedModule, uiModule)
        }
    }
}
