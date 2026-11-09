package com.airdesk.android.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.airdesk.android.AppViewModel
import com.airdesk.android.pairing.AdPairCodec
import com.airdesk.android.pairing.PairingValidator
import com.airdesk.android.pairing.PeerRecord
import com.google.zxing.BarcodeFormat
import com.journeyapps.barcodescanner.BarcodeEncoder
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import com.airdesk.android.ui.components.LabeledValue
import com.airdesk.android.ui.components.SectionCard
import com.airdesk.android.ui.components.StatusBadge
import com.airdesk.android.ui.formatEpochSeconds

@Composable
fun HomeScreen(viewModel: AppViewModel) {
    val context = LocalContext.current
    val identity = viewModel.identity
    val offer = viewModel.localOffer
    var pastedOffer by rememberSaveable { mutableStateOf("") }
    var peerLabel by rememberSaveable { mutableStateOf("") }
    var irohCodeInput by rememberSaveable { mutableStateOf("") }
    var irohPinInput by rememberSaveable { mutableStateOf("") }
    val qrScanner = rememberLauncherForActivityResult(ScanContract()) { result ->
        result.contents?.let { scanned ->
            irohCodeInput = scanned
            irohPinInput = ""
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
            .selectableGroup(),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("AirDesk", style = MaterialTheme.typography.headlineMedium)
        Text(
            "Android device-agent baseline",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        SectionCard(
            title = "Pairing status",
            subtitle = "AD-PAIR-1 now runs over direct Iroh with SAS confirmation. " +
                "The legacy local offer remains for diagnostics only.",
        ) {
            Text(
                "Direct pairing uses authenticated Iroh endpoint binding, no relay. " +
                    "Use the direct pairing section below for a secure session.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        SectionCard(title = "This device") {
            if (viewModel.identityError != null) {
                Text(
                    "Identity unavailable: ${viewModel.identityError}",
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            if (identity != null) {
                OutlinedTextField(
                    value = viewModel.displayNameDraft,
                    onValueChange = viewModel::updateDisplayNameDraft,
                    label = { Text("Display name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedButton(onClick = viewModel::saveDisplayName) {
                    Text("Save display name")
                }
                SelectionContainer {
                    LabeledValue(
                        label = "Device ID",
                        value = identity.deviceId,
                        monospace = true,
                    )
                }
                LabeledValue(
                    label = "Public key (base64url SPKI)",
                    value = identity.publicKeyBase64Url,
                    monospace = true,
                    maxLines = 3,
                )
                OutlinedButton(
                    onClick = {
                        copyToClipboard(context, "AirDesk public key", identity.publicKeyBase64Url)
                    },
                ) {
                    Text("Copy public key")
                }
            }
        }

        SectionCard(
            title = "Direct pairing over Iroh",
            subtitle = "AD-PAIR-1 runs over an encrypted, direct Iroh endpoint with " +
                "no relay dependency. Compare the six-digit code on both devices before trusting.",
        ) {
            val directCode = viewModel.irohCode
            val sas = viewModel.irohShortAuthenticationString
            viewModel.irohRoleLabel?.let { role ->
                Text(
                    "Role: $role",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (directCode != null) {
                val pin = viewModel.irohPin
                if (pin != null) {
                    LabeledValue(
                        label = "Pairing PIN",
                        value = pin,
                        monospace = true,
                    )
                    OutlinedButton(
                        onClick = {
                            copyToClipboard(context, "AirDesk pairing PIN", pin)
                        },
                    ) {
                        Text("Copy pairing PIN")
                    }
                } else {
                    QrCodeImage(directCode)
                }
                LabeledValue(
                    label = "Pairing code",
                    value = "Share this code with the other device",
                    monospace = false,
                )
                SelectionContainer {
                    Text(
                        directCode,
                        style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    )
                }
                OutlinedButton(
                    onClick = {
                        copyToClipboard(context, "AirDesk direct pairing code", directCode)
                    },
                ) {
                    Text("Copy pairing code")
                }
            }
            if (sas != null) {
                Text(
                    "Verification code: $sas",
                    style = MaterialTheme.typography.headlineSmall,
                    color = MaterialTheme.colorScheme.primary,
                )
                OutlinedTextField(
                    value = viewModel.irohVerificationCode,
                    onValueChange = viewModel::updateIrohVerificationCode,
                    label = { Text("Confirm code shown on the other device") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(
                    onClick = viewModel::confirmIrohShortAuthenticationString,
                    enabled = viewModel.irohVerificationCode.length == 6,
                ) {
                    Text("Confirm and trust peer")
                }
            } else if (directCode == null) {
                OutlinedButton(
                    onClick = { viewModel.startIrohHost(AdPairCodec.MODE_QR_SECRET) },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Create QR pairing code (host)")
                }
                OutlinedButton(
                    onClick = { viewModel.startIrohHost(AdPairCodec.MODE_PIN) },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Create PIN pairing code (host)")
                }
            }
            OutlinedTextField(
                value = irohCodeInput,
                onValueChange = { irohCodeInput = it },
                label = { Text("Paste pairing code from the host") },
                minLines = 3,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = irohPinInput,
                onValueChange = {
                    irohPinInput = it.filter(Char::isDigit).take(6)
                },
                label = { Text("Six-digit PIN (PIN pairing codes only)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                OutlinedButton(
                    onClick = {
                        qrScanner.launch(
                            ScanOptions().apply {
                                setDesiredBarcodeFormats(ScanOptions.QR_CODE)
                                setPrompt("Scan the AirDesk pairing QR code")
                                setBeepEnabled(false)
                                setOrientationLocked(false)
                            },
                        )
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Scan QR")
                }
                Button(
                    onClick = {
                        viewModel.joinIrohPairing(
                            irohCodeInput,
                            irohPinInput.takeIf { it.isNotBlank() },
                        )
                    },
                    enabled = irohCodeInput.isNotBlank() && sas == null,
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Join pairing")
                }
            }
            Text(
                viewModel.irohStatus,
                color = if (viewModel.irohStatusIsError) {
                    MaterialTheme.colorScheme.error
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                style = MaterialTheme.typography.bodySmall,
            )
            OutlinedButton(
                onClick = viewModel::cancelIrohPairing,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Cancel direct pairing")
            }
        }
        SectionCard(
            title = "Local pairing offer",
            subtitle = "Human-readable UI JSON (adfp / version 0.1 / kind pairing-offer). " +
                "A separate canonical ADFP FlatBuffers envelope is validated in Diagnostics. " +
                "Expires after ${PairingValidator.OFFER_LIFETIME_SECONDS / 60} minutes.",
        ) {
            if (offer == null) {
                Text(
                    "Offer unavailable until the device identity loads.",
                    style = MaterialTheme.typography.bodySmall,
                )
            } else {
                LabeledValue(
                    label = "Expires",
                    value = formatEpochSeconds(offer.offer.expiresAt),
                )
                SelectionContainer {
                    Text(
                        offer.json,
                        style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    )
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    OutlinedButton(
                        onClick = viewModel::regenerateOffer,
                        modifier = Modifier.weight(1f),
                    ) {
                        Text("Regenerate")
                    }
                    Button(
                        onClick = {
                            copyToClipboard(context, "AirDesk pairing offer", offer.json)
                        },
                        modifier = Modifier.weight(1f),
                    ) {
                        Text("Copy offer")
                    }
                }
            }
        }

        SectionCard(
            title = "Add a peer offer",
            subtitle = "Strict validation rejects malformed, expired, mismatched and replayed offers.",
        ) {
            OutlinedTextField(
                value = pastedOffer,
                onValueChange = {
                    pastedOffer = it
                    viewModel.clearPairingMessage()
                },
                label = { Text("Paste peer pairing-offer JSON") },
                minLines = 5,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = peerLabel,
                onValueChange = { peerLabel = it },
                label = { Text("Peer label (optional)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = {
                    viewModel.acceptPeerOffer(pastedOffer, peerLabel)
                },
                enabled = pastedOffer.isNotBlank(),
            ) {
                Text("Validate and add")
            }
            val message = viewModel.pairingMessage
            if (message != null) {
                Text(
                    message,
                    color = if (viewModel.pairingMessageIsError) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.secondary
                    },
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }

        SectionCard(
            title = "Paired peer registry",
            subtitle = "Local SharedPreferences only. Revocation is local and does not claim remote session invalidation.",
        ) {
            if (viewModel.peers.isEmpty()) {
                Text(
                    "No peers recorded.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                viewModel.peers.forEachIndexed { index, peer ->
                    key(peer.deviceId) {
                        PeerRow(
                            peer = peer,
                            onRevoke = { viewModel.revokePeer(peer.deviceId) },
                        )
                        if (index != viewModel.peers.lastIndex) {
                            HorizontalDivider()
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PeerRow(peer: PeerRecord, onRevoke: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                peer.displayName,
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.weight(1f),
            )
            val badgeColor = when {
                peer.revoked -> MaterialTheme.colorScheme.error
                !peer.trusted -> MaterialTheme.colorScheme.tertiary
                else -> MaterialTheme.colorScheme.secondary
            }
            StatusBadge(
                text = when {
                    peer.revoked -> "Revoked"
                    !peer.trusted -> "Pending SAS"
                    else -> "Active"
                },
                containerColor = badgeColor.copy(alpha = 0.16f),
                contentColor = badgeColor,
            )
        }
        LabeledValue("Device ID", peer.deviceId, monospace = true)
        LabeledValue(
            "Public key",
            peer.publicKey,
            monospace = true,
            maxLines = 1,
        )
        LabeledValue("Paired", formatEpochSeconds(peer.pairedAtEpochSeconds))
        LabeledValue("Capabilities", peer.capabilities.size.toString())
        if (!peer.revoked) {
            TextButton(onClick = onRevoke) {
                Text("Revoke locally", color = MaterialTheme.colorScheme.error)
            }
        } else if (peer.revokedAtEpochSeconds != null) {
            Text(
                "Revoked ${formatEpochSeconds(peer.revokedAtEpochSeconds)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun QrCodeImage(value: String) {
    val bitmap = remember(value) {
        runCatching {
            BarcodeEncoder().encodeBitmap(value, BarcodeFormat.QR_CODE, 720, 720)
        }.getOrNull()
    }
    if (bitmap == null) {
        Text(
            "Could not render the QR code. Use the copyable code below.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error,
        )
    } else {
        Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = "AirDesk direct pairing QR code",
            modifier = Modifier.size(220.dp),
        )
    }
}

private fun copyToClipboard(context: Context, label: String, value: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        ?: return
    clipboard.setPrimaryClip(ClipData.newPlainText(label, value))
}
