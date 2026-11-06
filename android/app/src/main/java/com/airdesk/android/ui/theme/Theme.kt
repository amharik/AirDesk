package com.airdesk.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColors = darkColorScheme(
    primary = Color(0xFF6FD3FF),
    onPrimary = Color(0xFF00212E),
    secondary = Color(0xFF9AE6B4),
    background = Color(0xFF0B1116),
    onBackground = Color(0xFFE1E8EE),
    surface = Color(0xFF101A21),
    onSurface = Color(0xFFE1E8EE),
    surfaceVariant = Color(0xFF1B2831),
    onSurfaceVariant = Color(0xFFB7C6D1),
    error = Color(0xFFFF8A80),
)

private val LightColors = lightColorScheme(
    primary = Color(0xFF006688),
    onPrimary = Color(0xFFFFFFFF),
    secondary = Color(0xFF2F6B47),
    background = Color(0xFFF7FAFC),
    onBackground = Color(0xFF152027),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF152027),
    surfaceVariant = Color(0xFFE6EDF2),
    onSurfaceVariant = Color(0xFF41525D),
    error = Color(0xFFB3261E),
)

@Composable
fun AirDeskTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content,
    )
}
