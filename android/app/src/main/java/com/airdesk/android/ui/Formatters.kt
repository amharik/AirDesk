package com.airdesk.android.ui

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private fun formatter(): DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss z", Locale.getDefault())

fun formatEpochSeconds(epochSeconds: Long): String =
    Instant.ofEpochSecond(epochSeconds)
        .atZone(ZoneId.systemDefault())
        .format(formatter())

fun formatEpochMillis(epochMillis: Long): String =
    Instant.ofEpochMilli(epochMillis)
        .atZone(ZoneId.systemDefault())
        .format(formatter())
