package com.airdesk.android.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.webkit.WebView
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.airdesk.android.AppViewModel
import com.airdesk.android.BuildConfig
import com.airdesk.android.capabilities.Authorization
import com.airdesk.android.capabilities.Availability
import com.airdesk.android.protocol.AdfpProtocol
import com.airdesk.android.ui.components.LabeledValue
import com.airdesk.android.ui.components.SectionCard
import com.airdesk.android.ui.formatEpochMillis

@Composable
fun DiagnosticsScreen(viewModel: AppViewModel) {
    val context = LocalContext.current
    val identity = viewModel.identity
    val webViewPackage = remember {
        runCatching { WebView.getCurrentWebViewPackage() }.getOrNull()
    }
    val cameraGranted = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.CAMERA,
    ) == PackageManager.PERMISSION_GRANTED

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Diagnostics", style = MaterialTheme.typography.headlineMedium)

        SectionCard(title = "Identity") {
            if (viewModel.identityError != null) {
                Text(
                    "Identity error: ${viewModel.identityError}",
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            if (identity == null) {
                Text("No identity loaded.", style = MaterialTheme.typography.bodySmall)
            } else {
                LabeledValue("Display name", identity.displayName)
                LabeledValue("Device ID", identity.deviceId, monospace = true)
                LabeledValue("Keystore alias", identity.alias, monospace = true)
                LabeledValue("Key algorithm", identity.keyAlgorithm)
                LabeledValue(
                    "Private key extractable",
                    identity.privateKeyExtractable.toString(),
                )
                LabeledValue("Key created", formatEpochMillis(identity.createdAtEpochMillis))
                SelectionContainer {
                    LabeledValue(
                        "Public key (base64url SPKI)",
                        identity.publicKeyBase64Url,
                        monospace = true,
                    )
                }
            }
        }

        SectionCard(
            title = "Pairing",
            subtitle = "Truthful baseline status. This is not a completed pairing protocol.",
        ) {
            LabeledValue("AD-PAIR-1 / SPAKE2+", "primitive, coordinator and wire session ready")
            LabeledValue("Session keys / channel binding", "derived; transport not connected")
            LabeledValue("Network transport", "none in this build")
            LabeledValue("Plaintext LAN fallback", "absent")
            LabeledValue("Peers recorded", viewModel.peers.size.toString())
            LabeledValue("Trusted peers", viewModel.peers.count { !it.revoked && it.trusted }.toString())
            LabeledValue("Pending peers", viewModel.peers.count { !it.revoked && !it.trusted }.toString())
            LabeledValue("Revoked peers", viewModel.peers.count { it.revoked }.toString())
        }

        SectionCard(
            title = "Canonical ADFP",
            subtitle = "FlatBuffers encode/decode diagnostics. No network transport or pairing crypto is active.",
        ) {
            LabeledValue("Envelope version", viewModel.adfpVersion)
            LabeledValue("File identifier", AdfpProtocol.FILE_IDENTIFIER)
            LabeledValue("FlatBuffers runtime", AdfpProtocol.FLATBUFFERS_RUNTIME_VERSION)
            LabeledValue("Max envelope bytes", AdfpProtocol.MAX_ENVELOPE_BYTES.toString())
            LabeledValue(
                "Last encoded envelope size",
                viewModel.lastEnvelopeSize?.let { "$it bytes" } ?: "not encoded",
            )
            val envelopeHash = viewModel.lastEnvelopeSha256
            if (envelopeHash == null) {
                LabeledValue("Last envelope SHA-256", "not encoded")
            } else {
                SelectionContainer {
                    LabeledValue("Last envelope SHA-256", envelopeHash, monospace = true)
                }
            }
            val selfTest = viewModel.decodeSelfTest
            LabeledValue(
                "Decode self-test",
                selfTest?.detail ?: "not run",
            )
            Text(
                "The offer shown in Connect is human-readable UI JSON. The canonical ADFP " +
                    "envelope is a separate FlatBuffers payload used for protocol validation.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        SectionCard(title = "Capabilities") {
            LabeledValue("Descriptors", viewModel.capabilities.size.toString())
            LabeledValue(
                "Available",
                viewModel.capabilities.count { it.availability == Availability.AVAILABLE }.toString(),
            )
            LabeledValue(
                "Restricted",
                viewModel.capabilities.count { it.availability == Availability.RESTRICTED }.toString(),
            )
            LabeledValue(
                "Granted",
                viewModel.capabilities.count { it.authorization == Authorization.GRANTED }.toString(),
            )
            LabeledValue("Camera permission", if (cameraGranted) "granted" else "not granted")
            LabeledValue("Filesystem scope", "app-private only; no device-wide filesystem")
        }

        SectionCard(title = "Presentation") {
            LabeledValue("Asset origin", "https://appassets.androidplatform.net")
            LabeledValue("Asset path", "/assets/DesktopShell/")
            LabeledValue("Loading mode", "WebViewAssetLoader")
            LabeledValue("JavaScript / DOM storage", "enabled")
            LabeledValue("File access", "disabled")
            LabeledValue(
                "WebView package",
                webViewPackage?.let { "${it.packageName} ${it.versionName ?: ""}".trim() }
                    ?: "unknown",
            )
        }

        SectionCard(title = "Build") {
            LabeledValue("Application ID", BuildConfig.APPLICATION_ID)
            LabeledValue("Version", "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
            LabeledValue("minSdk / targetSdk / compileSdk", "26 / 35 / 35")
            LabeledValue("Runtime Android SDK", Build.VERSION.SDK_INT.toString())
            LabeledValue("Device", "${Build.MANUFACTURER} ${Build.MODEL}".trim())
        }

        SectionCard(title = "Security baseline") {
            Text(
                "P-256 key is generated in Android Keystore and the private key is non-extractable. " +
                    "This build makes no claims about AD-PAIR-1, SPAKE2+, session authentication, " +
                    "grants, leases or remote transport.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
