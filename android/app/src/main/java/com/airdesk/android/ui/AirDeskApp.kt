package com.airdesk.android.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.viewmodel.compose.viewModel
import com.airdesk.android.AppViewModel
import com.airdesk.android.ui.screens.CapabilitiesScreen
import com.airdesk.android.ui.screens.DiagnosticsScreen
import com.airdesk.android.ui.screens.HomeScreen
import com.airdesk.android.ui.screens.PresentationScreen

private enum class AppTab(val label: String, val icon: ImageVector) {
    HOME("Connect", Icons.Filled.Home),
    CAPABILITIES("Capabilities", Icons.AutoMirrored.Filled.List),
    PRESENTATION("Desktop", Icons.Filled.PlayArrow),
    DIAGNOSTICS("Diagnostics", Icons.Filled.Settings),
}

@Composable
fun AirDeskApp(viewModel: AppViewModel = viewModel()) {
    var selected by rememberSaveable { mutableIntStateOf(0) }
    val tabs = AppTab.entries

    Scaffold(
        bottomBar = {
            NavigationBar {
                tabs.forEachIndexed { index, tab ->
                    NavigationBarItem(
                        selected = selected == index,
                        onClick = { selected = index },
                        icon = { Icon(tab.icon, contentDescription = tab.label) },
                        label = { Text(tab.label) },
                    )
                }
            }
        },
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            when (tabs[selected]) {
                AppTab.HOME -> HomeScreen(viewModel)
                AppTab.CAPABILITIES -> CapabilitiesScreen(viewModel)
                AppTab.PRESENTATION -> PresentationScreen()
                AppTab.DIAGNOSTICS -> DiagnosticsScreen(viewModel)
            }
        }
    }
}
