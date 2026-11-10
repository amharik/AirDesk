package com.airdesk.android

import android.Manifest
import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.IBinder
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.airdesk.android.capabilities.CapabilityCatalog
import com.airdesk.android.capabilities.CapabilityDescriptor
import com.airdesk.android.identity.DeviceIdentity
import com.airdesk.android.pairing.AdPairChannelBinding
import com.airdesk.android.pairing.AdPairCodec
import com.airdesk.android.pairing.AdPairCoordinator
import com.airdesk.android.pairing.AdPairIrohTransport
import com.airdesk.android.pairing.AdPairWireSession
import com.airdesk.android.pairing.AndroidAdPairSigner
import com.airdesk.android.pairing.AndroidAdPairVerifier
import com.airdesk.android.pairing.LocalOffer
import com.airdesk.android.pairing.LocalOfferFactory
import com.airdesk.android.pairing.PairingResult
import com.airdesk.android.pairing.PeerRecord
import com.airdesk.android.protocol.AdfpProtocol
import com.airdesk.android.protocol.AdfpSelfTestResult
import com.airdesk.android.remote.AndroidSSHService
import com.airdesk.android.remote.RemoteSSHContext
import com.airdesk.android.remote.RemoteSSHLease
import com.airdesk.android.remote.RemoteSSHLeaseRegistry
import com.airdesk.android.remote.RemoteSSHOperation
import com.airdesk.android.remote.RemoteSSHServiceController
import com.airdesk.android.remote.RemoteTerminalProfileDraft
import com.airdesk.android.workspace.DisplaySessionController
import java.util.UUID
import kotlinx.coroutines.launch

class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val container = (application as AirDeskApplication).container

    val displaySession = DisplaySessionController()

    var remoteTerminalProfile by mutableStateOf(RemoteTerminalProfileDraft())
        private set
    var remoteTerminalService by mutableStateOf<RemoteSSHServiceController?>(null)
        private set
    var remoteTerminalLeaseId by mutableStateOf<String?>(null)
        private set
    var remoteTerminalMessage by mutableStateOf<String?>(null)
        private set
    private var remoteTerminalBound = false
    private val remoteTerminalConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val local = service as? AndroidSSHService.LocalBinder ?: return
            val controller = local.controller()
            val leaseId = remoteTerminalLeaseId
            if (leaseId != null && controller.terminal.lease(leaseId) == null) {
                remoteTerminalLeaseId = null
            }
            remoteTerminalService = controller
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            remoteTerminalService = null
            remoteTerminalLeaseId = null
        }

        override fun onBindingDied(name: ComponentName?) {
            remoteTerminalService = null
            remoteTerminalLeaseId = null
        }
    }

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
        bindRemoteTerminalService()
    }

    fun ensureRemoteTerminalService() {
        if (remoteTerminalService == null) {
            bindRemoteTerminalService()
        }
    }

    fun applyRemoteTerminalProfile(
        draft: RemoteTerminalProfileDraft,
        authorize: Boolean,
    ): String? {
        if (draft.enabled) {
            runCatching { draft.configuration() }.getOrElse { error ->
                return error.message ?: "The remote terminal profile is invalid."
            }
        }
        remoteTerminalProfile = draft
        if (!draft.enabled) {
            remoteTerminalLeaseId?.let { leaseId ->
                remoteTerminalService?.terminal?.revokeLease(leaseId)
            }
            remoteTerminalLeaseId = null
            remoteTerminalMessage = "Remote terminal disabled."
            return null
        }
        if (authorize) {
            return authorizeRemoteTerminal()
        }
        remoteTerminalMessage =
            "Profile saved. Authorize this session before the terminal can connect."
        return null
    }

    fun authorizeRemoteTerminal(): String? {
        val profile = remoteTerminalProfile
        if (!profile.enabled) {
            return "Enable the remote terminal before authorizing it."
        }
        runCatching { profile.configuration() }.getOrElse { error ->
            return error.message ?: "The remote terminal profile is invalid."
        }
        val currentIdentity = identity ?: return "The device identity is not loaded."
        val controller = remoteTerminalService
            ?: return "The remote terminal service is not connected yet. Try again."
        val now = System.currentTimeMillis()
        remoteTerminalLeaseId?.let { existing ->
            controller.terminal.revokeLease(existing, "Replaced by a new authorization")
        }
        val lease = RemoteSSHLease(
            leaseId = UUID.randomUUID().toString(),
            capUri = RemoteSSHLeaseRegistry.CAPABILITY_URI,
            workspaceId = displaySession.snapshot().workspace,
            applicationId = REMOTE_TERMINAL_APPLICATION_ID,
            requesterDeviceId = currentIdentity.deviceId,
            sessionId = displaySession.sessionId,
            issuedAtEpochMillis = now,
            expiresAtEpochMillis = now + REMOTE_TERMINAL_LEASE_MILLIS,
            operations = RemoteSSHOperation.entries.toSet(),
            auditId = UUID.randomUUID().toString(),
        )
        return runCatching {
            controller.terminal.grantLease(lease)
            remoteTerminalLeaseId = lease.leaseId
            remoteTerminalMessage = "Authorized this session for the remote terminal."
            null
        }.getOrElse { error ->
            error.message ?: "The remote terminal could not be authorized."
        }
    }

    fun remoteTerminalConfiguration() = remoteTerminalProfile.configuration()

    fun remoteTerminalContext(): RemoteSSHContext = RemoteSSHContext(
        capUri = RemoteSSHLeaseRegistry.CAPABILITY_URI,
        workspaceId = displaySession.snapshot().workspace,
        applicationId = REMOTE_TERMINAL_APPLICATION_ID,
        requesterDeviceId = identity?.deviceId.orEmpty(),
        sessionId = displaySession.sessionId,
        leaseId = remoteTerminalLeaseId,
    )

    fun clearRemoteTerminalMessage() {
        remoteTerminalMessage = null
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

    var irohCode by mutableStateOf<String?>(null)
        private set
    var irohShortAuthenticationString by mutableStateOf<String?>(null)
        private set
    var irohStatus by mutableStateOf("Iroh endpoint not started")
        private set
    var irohStatusIsError by mutableStateOf(false)
        private set
    var irohVerificationCode by mutableStateOf("")
        private set
    var irohRoleLabel by mutableStateOf<String?>(null)
        private set
    var irohPin by mutableStateOf<String?>(null)
        private set
    var irohPairingMode by mutableStateOf(AdPairCodec.MODE_QR_SECRET)
        private set
    var irohJoinPin by mutableStateOf("")
        private set

    private var irohTransport: AdPairIrohTransport? = null

    fun startIrohHost(mode: String = AdPairCodec.MODE_QR_SECRET) {
        val current = identity ?: return
        cancelIrohPairing()
        irohRoleLabel = "Host"
        irohPairingMode = mode
        irohStatus = "Starting direct Iroh endpoint..."
        irohStatusIsError = false
        viewModelScope.launch {
            runCatching {
                val endpoint = container.irohPeer.start()
                val session = AdPairWireSession(
                    AdPairWireSession.Role.HOST,
                    pairingCoordinator(current, AdPairCoordinator.Role.INITIATOR),
                )
                val transport = AdPairIrohTransport(session, container.irohPeer)
                irohTransport = transport
                val challenge = session.startHost(
                    mode = mode,
                    channelBinding = AdPairChannelBinding("iroh-endpoint", endpoint.endpointId),
                    endpointHint = endpoint.ticket,
                    capabilities = capabilities.map { it.capUri },
                )
                irohCode = challenge.serialized
                irohPin = challenge.pin
                irohVerificationCode = ""
                irohShortAuthenticationString = null
                irohStatus = if (mode == AdPairCodec.MODE_PIN) {
                    "Share the pairing code and six-digit PIN with the other device."
                } else {
                    "Waiting for the other device to scan or paste the QR code over Iroh..."
                }
                launch {
                    runCatching {
                        transport.accept { refreshIrohState(it) }
                    }.onFailure { reportIrohError(it) }
                }
            }.onFailure { reportIrohError(it) }
        }
    }

    fun updateIrohJoinPin(value: String) {
        irohJoinPin = value.filter(Char::isDigit).take(6)
    }

    fun joinIrohPairing(code: String, pin: String? = null) {
        val current = identity ?: return
        cancelIrohPairing()
        irohRoleLabel = "Controller"
        irohStatus = "Connecting over Iroh..."
        irohStatusIsError = false
        viewModelScope.launch {
            runCatching {
                val parsed = AdPairCodec.parse(
                    code.trim(),
                    nowEpochMillis = System.currentTimeMillis(),
                    localDeviceId = current.deviceId,
                )
                val binding = parsed.offer.channelBinding
                require(binding.kind == "iroh-endpoint") { "pairing code does not use an Iroh endpoint binding" }
                val ticket = parsed.offer.endpointHint
                    ?: error("pairing code does not include an Iroh ticket")
                val endpoint = container.irohPeer.start()
                val session = AdPairWireSession(
                    AdPairWireSession.Role.CONTROLLER,
                    pairingCoordinator(current, AdPairCoordinator.Role.RESPONDER),
                )
                val response = session.join(
                    code = code.trim(),
                    pin = pin,
                    endpointHint = endpoint.ticket,
                    capabilities = capabilities.map { it.capUri },
                )
                val transport = AdPairIrohTransport(session, container.irohPeer)
                irohTransport = transport
                irohCode = null
                irohPin = null
                irohVerificationCode = ""
                irohShortAuthenticationString = null
                transport.connect(
                    ticket = ticket,
                    expectedEndpointId = binding.value,
                    initialMessage = response,
                ) { refreshIrohState(it) }
                irohStatus = "Connected over Iroh; compare the verification code."
            }.onFailure { reportIrohError(it) }
        }
    }

    fun updateIrohVerificationCode(value: String) {
        irohVerificationCode = value.filter(Char::isDigit).take(6)
    }

    fun confirmIrohShortAuthenticationString() {
        val transport = irohTransport ?: return
        runCatching {
            transport.confirmShortAuthenticationString(irohVerificationCode)
        }.onSuccess {
            irohStatus = "Direct pairing complete"
            irohStatusIsError = false
            refreshPeers()
        }.onFailure { reportIrohError(it) }
    }

    fun cancelIrohPairing() {
        irohTransport?.close()
        irohTransport = null
        irohCode = null
        irohPin = null
        irohShortAuthenticationString = null
        irohRoleLabel = null
        irohVerificationCode = ""
        irohJoinPin = ""
        irohStatus = "Iroh pairing cancelled"
        irohStatusIsError = false
    }

    override fun onCleared() {
        if (remoteTerminalBound) {
            runCatching {
                getApplication<Application>().unbindService(remoteTerminalConnection)
            }
            remoteTerminalBound = false
        }
        remoteTerminalService = null
        irohTransport?.close()
        irohTransport = null
        super.onCleared()
    }

    private fun bindRemoteTerminalService() {
        if (remoteTerminalBound) return
        val application = getApplication<Application>()
        val intent = Intent(application, AndroidSSHService::class.java)
        remoteTerminalBound = runCatching {
            application.bindService(intent, remoteTerminalConnection, Context.BIND_AUTO_CREATE)
        }.getOrDefault(false)
    }

    private fun pairingCoordinator(
        current: DeviceIdentity,
        role: AdPairCoordinator.Role,
    ): AdPairCoordinator = AdPairCoordinator(
        role = role,
        deviceId = current.deviceId,
        publicKey = current.publicKeyBase64Url,
        signer = AndroidAdPairSigner(container.identityStore),
        verifier = AndroidAdPairVerifier(),
        registry = container.peerRegistry,
        peerDisplayLabel = null,
    )

    private fun refreshIrohState(transport: AdPairIrohTransport) {
        viewModelScope.launch {
            irohShortAuthenticationString = transport.shortAuthenticationString
            irohStatus = when (transport.state) {
                AdPairWireSession.State.AWAITING_USER_VERIFICATION ->
                    "Pairing transcript verified; compare the 6-digit code on both devices."
                AdPairWireSession.State.COMPLETED -> "Direct pairing complete"
                AdPairWireSession.State.FAILED ->
                    "Pairing failed: ${transport.lastError ?: "unknown error"}"
                AdPairWireSession.State.WAITING_FOR_CONTROLLER ->
                    "Waiting for the other device to join over Iroh..."
                AdPairWireSession.State.AWAITING_SHARE,
                AdPairWireSession.State.AWAITING_VERIFIER_RESPONSE,
                AdPairWireSession.State.AWAITING_INITIATOR_FINISH,
                -> "Exchanging authenticated pairing messages over Iroh..."
                AdPairWireSession.State.IDLE -> "Iroh pairing idle"
            }
            irohStatusIsError = transport.state == AdPairWireSession.State.FAILED
            if (transport.state == AdPairWireSession.State.COMPLETED) {
                refreshPeers()
            }
        }
    }

    private fun reportIrohError(error: Throwable) {
        viewModelScope.launch {
            irohStatus = error.message ?: error.javaClass.simpleName
            irohStatusIsError = true
        }
    }

    companion object {
        private const val REMOTE_TERMINAL_APPLICATION_ID = "terminal"
        private const val REMOTE_TERMINAL_LEASE_MILLIS = 8L * 60 * 60 * 1_000
    }
}
