package com.airdesk.android.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.airdesk.android.AppViewModel
import com.airdesk.android.capabilities.Authorization
import com.airdesk.android.capabilities.Availability
import com.airdesk.android.capabilities.CapabilityCatalog
import com.airdesk.android.capabilities.CapabilityDescriptor
import com.airdesk.android.ui.components.LabeledValue
import com.airdesk.android.ui.components.SectionCard
import com.airdesk.android.ui.components.StatusBadge

@Composable
fun CapabilitiesScreen(viewModel: AppViewModel) {
    val context = LocalContext.current
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) {
        viewModel.refreshCapabilities()
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        viewModel.refreshCapabilities()
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
        Text("Capabilities", style = MaterialTheme.typography.headlineMedium)
        Text(
            "Availability and authorization are separate. Pairing does not grant a capability, " +
                "and no grants or leases are issued in this baseline.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        SectionCard(
            title = "Camera permission",
            subtitle = "Android permission state is read from the platform and shown without being " +
                "collapsed into authorization.",
        ) {
            LabeledValue(
                "android.permission.CAMERA",
                if (cameraGranted) "granted" else "not granted",
            )
            if (!cameraGranted) {
                Button(onClick = {
                    permissionLauncher.launch(Manifest.permission.CAMERA)
                }) {
                    Text("Request camera permission")
                }
            }
        }

        viewModel.capabilities.forEach { capability ->
            CapabilityCard(capability)
        }
    }
}

@Composable
private fun CapabilityCard(capability: CapabilityDescriptor) {
    SectionCard(title = capability.label) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            AvailabilityBadge(capability.availability)
            AuthorizationBadge(capability.authorization)
        }
        LabeledValue("cap_uri", capability.capUri, monospace = true)
        Text(capability.summary, style = MaterialTheme.typography.bodySmall)
        Text(
            "Permissions: " + capability.permissions.ifEmpty { listOf("none") }.joinToString(),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            capability.note,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun AvailabilityBadge(availability: Availability) {
    val colors = when (availability) {
        Availability.AVAILABLE -> badgeColors(0xFF2E7D32)
        Availability.BUSY -> badgeColors(0xFF8D6E00)
        Availability.RESTRICTED -> badgeColors(0xFFB35C00)
        Availability.UNAVAILABLE -> badgeColors(0xFF7A7A7A)
    }
    StatusBadge("availability: ${availability.name.lowercase()}", colors.first, colors.second)
}

@Composable
private fun AuthorizationBadge(authorization: Authorization) {
    val colors = when (authorization) {
        Authorization.UNGRANTED -> badgeColors(0xFF326A8A)
        Authorization.GRANTED -> badgeColors(0xFF2E7D32)
        Authorization.DENIED -> badgeColors(0xFF9B2C2C)
        Authorization.REVOKED -> badgeColors(0xFF6D1B1B)
    }
    StatusBadge("authorization: ${authorization.name.lowercase()}", colors.first, colors.second)
}

@Composable
private fun badgeColors(rgb: Long): Pair<Color, Color> {
    val base = Color(rgb)
    return base.copy(alpha = 0.18f) to base
}
