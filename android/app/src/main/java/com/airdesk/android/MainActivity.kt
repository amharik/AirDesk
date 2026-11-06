package com.airdesk.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.airdesk.android.ui.AirDeskApp
import com.airdesk.android.ui.theme.AirDeskTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AirDeskTheme {
                AirDeskApp()
            }
        }
    }
}
