package com.airdesk.android.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.airdesk.android.AppViewModel
import com.airdesk.android.pairing.PairingValidator
import com.airdesk.android.pairing.PeerRecord
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
            title = "Pairing baseline, not AD-PAIR-1",
            subtitle = "The offer format and local peer registry are implemented. " +
                "AD-PAIR-1 / SPAKE2+ is not connected, and this build does not claim a secure pairing session.",
        ) {
            Text(
                "No session keys, no channel binding and no LAN transport are active. " +
                    "Pairing here only records a validated peer offer locally.",
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

private fun copyToClipboard(context: Context, label: String, value: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        ?: return
    clipboard.setPrimaryClip(ClipData.newPlainText(label, value))
}
