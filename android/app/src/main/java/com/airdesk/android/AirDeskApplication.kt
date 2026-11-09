package com.airdesk.android

import android.app.Application
import android.content.Context
import com.airdesk.android.fabric.IrohFabricPeer
import com.airdesk.android.identity.DeviceIdentity
import com.airdesk.android.identity.DeviceIdentityStore
import com.airdesk.android.pairing.NonceStore
import com.airdesk.android.pairing.PairingService
import com.airdesk.android.pairing.PeerRegistry
import com.airdesk.android.pairing.SharedPreferencesKeyValueStore
import computer.iroh.IrohAndroid

class AirDeskApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        IrohAndroid.installAndroidContext(this)
    }

    val container: AppContainer by lazy { AppContainer(this) }
}

class AppContainer(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences("airdesk_state", Context.MODE_PRIVATE)
    private val keyValueStore = SharedPreferencesKeyValueStore(prefs)

    val identityStore = DeviceIdentityStore(context)
    val identity: DeviceIdentity by lazy { identityStore.loadOrCreate() }
    val peerRegistry = PeerRegistry(keyValueStore)
    val nonceStore = NonceStore(keyValueStore)
    val pairingService = PairingService(peerRegistry, nonceStore)
    val irohPeer: IrohFabricPeer by lazy { IrohFabricPeer(context) }
}
