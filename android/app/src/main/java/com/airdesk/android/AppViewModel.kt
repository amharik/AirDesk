package com.airdesk.android

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import com.airdesk.android.capabilities.CapabilityCatalog
import com.airdesk.android.capabilities.CapabilityDescriptor
import com.airdesk.android.identity.DeviceIdentity
import com.airdesk.android.pairing.LocalOffer
import com.airdesk.android.pairing.LocalOfferFactory
import com.airdesk.android.pairing.PairingResult
import com.airdesk.android.pairing.PeerRecord
import com.airdesk.android.protocol.AdfpProtocol
import com.airdesk.android.protocol.AdfpSelfTestResult

class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val container = (application as AirDeskApplication).container

    var identity by mutableStateOf<DeviceIdentity?>(null)
        private set
    var identityError by mutableStateOf<String?>(null)
        private set
    var peers by mutableStateOf<List<PeerRecord>>(emptyList())
        private set
    var capabilities by mutableStateOf<List<CapabilityDescriptor>>(emptyList())
        private set
    var localOffer by mutableStateOf<LocalOffer?>(null)
        private set
    var pairingMessage by mutableStateOf<String?>(null)
        private set
    var pairingMessageIsError by mutableStateOf(false)
        private set
    var displayNameDraft by mutableStateOf("")
        private set
    val adfpVersion: String = AdfpProtocol.versionLabel()
    var lastEnvelopeSize by mutableStateOf<Int?>(null)
        private set
    var lastEnvelopeSha256 by mutableStateOf<String?>(null)
        private set
    var decodeSelfTest by mutableStateOf<AdfpSelfTestResult?>(null)
        private set

    init {
        runCatching { container.identity }
            .onSuccess { loaded ->
                identity = loaded
                displayNameDraft = loaded.displayName
                refreshPeers()
                refreshCapabilities()
                regenerateOffer()
            }
            .onFailure { error ->
                identityError = error.message ?: error::class.java.simpleName
                refreshCapabilities()
            }
    }

    fun refreshCapabilities() {
        val context = getApplication<Application>()
        val cameraHardware = context.packageManager
            .hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
        val cameraGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.CAMERA,
        ) == PackageManager.PERMISSION_GRANTED
        capabilities = CapabilityCatalog.seed(
            providerDeviceId = identity?.deviceId.orEmpty(),
            cameraHardware = cameraHardware,
            cameraPermissionGranted = cameraGranted,
        )
    }

    fun refreshPeers() {
        peers = container.peerRegistry.all()
    }

    fun regenerateOffer() {
        val current = identity ?: return
        val generated = LocalOfferFactory.create(
            identity = current,
            capabilities = capabilities.map { it.capUri },
            nowEpochSeconds = System.currentTimeMillis() / 1000L,
        )
        localOffer = generated
        generated.canonical?.let { canonical ->
            lastEnvelopeSize = canonical.bytes.size
            lastEnvelopeSha256 = canonical.sha256Hex
            decodeSelfTest = AdfpProtocol.selfTest(canonical)
        }
    }

    fun updateDisplayNameDraft(value: String) {
        displayNameDraft = value
    }

    fun saveDisplayName() {
        val trimmed = displayNameDraft.trim()
        if (trimmed.isEmpty()) {
            pairingMessage = "Display name cannot be empty"
            pairingMessageIsError = true
            return
        }
        runCatching { container.identityStore.setDisplayName(trimmed) }
            .onSuccess { saved ->
                identity = identity?.copy(displayName = saved)
                displayNameDraft = saved
                pairingMessage = "Display name saved"
                pairingMessageIsError = false
            }
            .onFailure {
                pairingMessage = "Could not save display name"
                pairingMessageIsError = true
            }
    }

    fun acceptPeerOffer(text: String, label: String) {
        val result = container.pairingService.accept(
            text = text,
            ownDeviceId = identity?.deviceId,
            label = label,
        )
        when (result) {
            is PairingResult.Accepted -> {
                pairingMessage = "Peer offer validated and added to the local registry"
                pairingMessageIsError = false
                refreshPeers()
            }
            is PairingResult.Rejected -> {
                pairingMessage = "${result.error}: ${result.message}"
                pairingMessageIsError = true
            }
        }
    }

    fun clearPairingMessage() {
        pairingMessage = null
    }

    fun revokePeer(deviceId: String) {
        val revoked = container.peerRegistry.revoke(
            deviceId,
            System.currentTimeMillis() / 1000L,
        )
        pairingMessage = if (revoked) {
            "Peer revoked locally"
        } else {
            "Peer not found"
        }
        pairingMessageIsError = !revoked
        refreshPeers()
    }
}
