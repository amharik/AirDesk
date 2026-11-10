package com.airdesk.android.ui.screens

import android.annotation.SuppressLint
import android.net.Uri
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.WebViewAssetLoader
import com.airdesk.android.AppViewModel
import com.airdesk.android.BuildConfig
import com.airdesk.android.remote.AndroidSSHService
import com.airdesk.android.remote.RemoteSSHHostBridge
import com.airdesk.android.workspace.AndroidWorkspaceHost
import com.airdesk.android.workspace.DisplaySessionSnapshot
import java.io.ByteArrayInputStream

@Suppress("DEPRECATION")
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun PresentationScreen(viewModel: AppViewModel) {
    val context = LocalContext.current
    val session = viewModel.displaySession
    val workspaceName = viewModel.identity?.displayName
        ?.takeIf { it.isNotBlank() }
        ?: "Android workspace"
    val host = remember(session) {
        AndroidWorkspaceHost(session = session, workspaceName = workspaceName)
    }
    val remoteProfile = viewModel.remoteTerminalProfile
    val remoteController = viewModel.remoteTerminalService
    var showRemoteSettings by remember { mutableStateOf(false) }
    var snapshot by remember(session) { mutableStateOf(session.snapshot()) }

    LaunchedEffect(Unit) {
        viewModel.ensureRemoteTerminalService()
    }

    LaunchedEffect(remoteProfile) {
        host.updateRemoteTerminalProfile(remoteProfile)
    }

    DisposableEffect(host, remoteController) {
        val controller = remoteController
        if (controller == null) {
            host.terminalHandler = null
            onDispose { }
        } else {
            val bridge = RemoteSSHHostBridge(
                controller = controller,
                output = host,
                configuration = viewModel::remoteTerminalConfiguration,
                context = viewModel::remoteTerminalContext,
            )
            bridge.onStartRequested = { AndroidSSHService.start(context) }
            bridge.onStopRequested = { AndroidSSHService.stop(context) }
            host.terminalHandler = bridge::handle
            bridge.attach()
            onDispose {
                host.terminalHandler = null
                bridge.detach()
            }
        }
    }
    val assetLoader = remember {
        WebViewAssetLoader.Builder()
            .setDomain(AndroidWorkspaceHost.ASSET_DOMAIN)
            .addPathHandler(
                "/assets/",
                WebViewAssetLoader.AssetsPathHandler(context.applicationContext),
            )
            .build()
    }
    var webView by remember { mutableStateOf<WebView?>(null) }

    DisposableEffect(session) {
        val listener: (DisplaySessionSnapshot) -> Unit = { snapshot = it }
        session.addListener(listener)
        onDispose { session.removeListener(listener) }
    }

    DisposableEffect(host) {
        onDispose {
            host.detach()
            webView?.apply {
                stopLoading()
                loadUrl("about:blank")
                destroy()
            }
            webView = null
        }
    }

    val displaySummary = snapshot.displayStream?.let { stream ->
        "${stream.state.wire} · ${stream.codec.wire} " +
            (if (stream.hardwareAccelerated) "hardware" else "software") +
            (if (stream.fallback) " fallback" else "") +
            " · ${stream.width}×${stream.height} · " +
            "${stream.metrics.encodedFrames} frames"
    } ?: "idle · no codec"

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Presentation", style = MaterialTheme.typography.headlineMedium)
            OutlinedButton(onClick = { showRemoteSettings = true }) {
                Text("SSH setup")
            }
        }
        Text(
            "DesktopShell is served from bundled assets through WebViewAssetLoader at a stable " +
                "https origin. External navigation and non-local requests are blocked.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            AndroidWorkspaceHost.START_URL,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            "Bridge ${snapshot.phase.wire} · session ${snapshot.sessionId.take(12)} · " +
                "generation ${snapshot.generation} · ${snapshot.workspace}",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.primary,
        )
        Text(
            "Runtime ${snapshot.runtimeState ?: "waiting"} · viewport " +
                (snapshot.viewport?.let { "${it.width}×${it.height}" } ?: "—") +
                " · terminal ${snapshot.terminalStatus ?: "idle"}",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            "Remote ${remoteProfile.destination} · " +
                (if (remoteProfile.enabled) "enabled" else "disabled") +
                " · " +
                (if (viewModel.remoteTerminalLeaseId != null) {
                    "authorized"
                } else {
                    "not authorized"
                }) +
                (viewModel.remoteTerminalMessage?.let { " · $it" } ?: ""),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            "Display $displaySummary",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        snapshot.displayStream?.lastError?.let { error ->
            Text(
                "Display error: $error",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        snapshot.lastError?.let { error ->
            Text(
                "Desktop error: $error",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        snapshot.lastBridgeRejection?.let { rejection ->
            Text(
                "Bridge rejection: $rejection",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        Spacer(Modifier.height(12.dp))
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .border(
                    width = 1.dp,
                    color = MaterialTheme.colorScheme.outlineVariant,
                    shape = RoundedCornerShape(12.dp),
                ),
        ) {
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { viewContext ->
                    WebView(viewContext).apply {
                        webView = this
                        WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG)
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.allowFileAccess = false
                        settings.allowContentAccess = false
                        settings.allowFileAccessFromFileURLs = false
                        settings.allowUniversalAccessFromFileURLs = false
                        settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                        settings.mediaPlaybackRequiresUserGesture = true
                        settings.javaScriptCanOpenWindowsAutomatically = false
                        settings.setSupportMultipleWindows(false)
                        settings.cacheMode = WebSettings.LOAD_DEFAULT
                        webViewClient = object : WebViewClient() {
                            override fun shouldOverrideUrlLoading(
                                view: WebView?,
                                request: WebResourceRequest?,
                            ): Boolean {
                                val uri = request?.url ?: return true
                                return !isLocalAsset(uri)
                            }

                            override fun shouldInterceptRequest(
                                view: WebView?,
                                request: WebResourceRequest?,
                            ): WebResourceResponse? {
                                val uri = request?.url ?: return blockedResponse()
                                return when (uri.scheme) {
                                    "https" -> {
                                        if (isLocalAsset(uri)) {
                                            assetLoader.shouldInterceptRequest(uri) ?: blockedResponse()
                                        } else {
                                            blockedResponse()
                                        }
                                    }
                                    "data", "blob", "about" -> null
                                    else -> blockedResponse()
                                }
                            }

                            override fun onReceivedError(
                                view: WebView?,
                                request: WebResourceRequest?,
                                error: WebResourceError?,
                            ) {
                                if (request?.isForMainFrame != true) return
                                session.markFailure(
                                    "Desktop load failed: ${error?.description ?: "unknown error"}",
                                )
                            }
                        }
                        host.updateRemoteTerminalProfile(viewModel.remoteTerminalProfile)
                        host.attachAndLoad(this)
                    }
                },
            )
        }
    }

    if (showRemoteSettings) {
        RemoteTerminalSettingsDialog(
            profile = remoteProfile,
            status = viewModel.remoteTerminalMessage,
            leaseAuthorized = viewModel.remoteTerminalLeaseId != null,
            serviceConnected = remoteController != null,
            onDismiss = {
                showRemoteSettings = false
                viewModel.clearRemoteTerminalMessage()
            },
            onApply = { draft, authorize ->
                val error = viewModel.applyRemoteTerminalProfile(draft, authorize)
                if (error == null) {
                    host.updateRemoteTerminalProfile(
                        profile = viewModel.remoteTerminalProfile,
                        restart = true,
                    )
                    showRemoteSettings = false
                }
                error
            },
            onAuthorize = { viewModel.authorizeRemoteTerminal() },
        )
    }
}

private fun isLocalAsset(uri: Uri): Boolean =
    uri.scheme == "https" &&
        uri.host == AndroidWorkspaceHost.ASSET_DOMAIN &&
        uri.path?.startsWith(AndroidWorkspaceHost.ASSET_PREFIX) == true

private fun blockedResponse(): WebResourceResponse =
    WebResourceResponse(
        "text/plain",
        "utf-8",
        403,
        "Blocked",
        emptyMap(),
        ByteArrayInputStream(ByteArray(0)),
    )
