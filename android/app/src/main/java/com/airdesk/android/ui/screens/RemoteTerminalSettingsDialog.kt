package com.airdesk.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.airdesk.android.remote.RemoteTerminalProfileDraft

@Composable
fun RemoteTerminalSettingsDialog(
    profile: RemoteTerminalProfileDraft,
    status: String?,
    leaseAuthorized: Boolean,
    serviceConnected: Boolean,
    onDismiss: () -> Unit,
    onApply: (RemoteTerminalProfileDraft, Boolean) -> String?,
    onAuthorize: () -> String?,
) {
    var enabled by remember { mutableStateOf(profile.enabled) }
    var host by remember { mutableStateOf(profile.host) }
    var port by remember { mutableStateOf(profile.port) }
    var username by remember { mutableStateOf(profile.username) }
    var password by remember { mutableStateOf(profile.password) }
    var hostKey by remember { mutableStateOf(profile.hostKey) }
    var startupCommand by remember { mutableStateOf(profile.startupCommand) }
    var error by remember { mutableStateOf<String?>(null) }

    fun draft(): RemoteTerminalProfileDraft = RemoteTerminalProfileDraft(
        enabled = enabled,
        host = host,
        port = port,
        username = username,
        password = password,
        hostKey = hostKey,
        startupCommand = startupCommand,
    )

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Remote terminal") },
        text = {
            Column(
                modifier = Modifier
                    .verticalScroll(rememberScrollState())
                    .padding(vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Use SSH remote terminal")
                        Text(
                            "Runs inside a foreground service so the session survives app backgrounding.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Switch(checked = enabled, onCheckedChange = { enabled = it })
                }
                OutlinedTextField(
                    value = host,
                    onValueChange = { host = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Host") },
                    singleLine = true,
                )
                OutlinedTextField(
                    value = port,
                    onValueChange = { port = it.filter(Char::isDigit).take(5) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Port") },
                    singleLine = true,
                )
                OutlinedTextField(
                    value = username,
                    onValueChange = { username = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Username") },
                    singleLine = true,
                )
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Password") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                )
                OutlinedTextField(
                    value = hostKey,
                    onValueChange = { hostKey = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Pinned OpenSSH host key") },
                    minLines = 2,
                )
                OutlinedTextField(
                    value = startupCommand,
                    onValueChange = { startupCommand = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Startup command") },
                    singleLine = true,
                )
                if (enabled) {
                    Text(
                        if (serviceConnected) {
                            "The SSH password stays in memory and is never written to disk."
                        } else {
                            "Connecting to the foreground service..."
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        if (leaseAuthorized) {
                            "This session has a scoped capability lease."
                        } else {
                            "A scoped capability lease is required before the terminal can connect."
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    TextButton(
                        onClick = {
                            error = onAuthorize()
                        },
                    ) {
                        Text("Authorize this session")
                    }
                }
                status?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
                error?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    error = onApply(draft(), true)
                },
            ) {
                Text("Save & authorize")
            }
        },
        dismissButton = {
            Row {
                TextButton(onClick = onDismiss) {
                    Text("Cancel")
                }
                TextButton(
                    onClick = {
                        error = onApply(draft(), false)
                    },
                ) {
                    Text("Save")
                }
            }
        },
    )
}
