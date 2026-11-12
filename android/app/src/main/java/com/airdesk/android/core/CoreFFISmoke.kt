package com.airdesk.android.core

import com.airdesk.android.BuildConfig
import com.airdesk.core.coreAbiVersion
import com.airdesk.core.coreIsAbiCompatible
import com.airdesk.core.coreSmokeLabel

object CoreFFISmoke {
    fun label(): String? = if (BuildConfig.DEBUG) coreSmokeLabel() else null

    fun isCurrentAbiCompatible(): Boolean =
        BuildConfig.DEBUG && coreIsAbiCompatible(coreAbiVersion())
}
