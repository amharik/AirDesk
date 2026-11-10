package com.airdesk.android.workspace

import android.net.Uri
import android.os.Build
import android.webkit.WebView
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.airdesk.android.remote.RemoteSSHHostOutput
import com.airdesk.android.remote.RemoteTerminalProfileDraft
import kotlin.math.roundToInt
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put

class AndroidWorkspaceHost(
    private val session: DisplaySessionController,
    private val workspaceName: String,
    private val deviceName: String = Build.MODEL.ifBlank { "Android" },
) : RemoteSSHHostOutput {
    private val bridge = AndroidDesktopBridge(session.sessionId, session.currentGeneration)
    private val json = Json { ignoreUnknownKeys = true }
    private var webView: WebView? = null
    private var bridgeView: WebView? = null
    private var bridgeAttached = false
    private var remoteTerminalBootstrap = "{\"enabled\":false}"

    var terminalHandler: ((AndroidTerminalMessage) -> Unit)? = null

    init {
        bridge.onRuntimeMessage = ::handleRuntimeMessage
        bridge.onTerminalMessage = ::handleTerminalMessage
    }

    fun attachAndLoad(view: WebView) {
        webView = view
        if (bridgeView !== view) {
            bridgeAttached = attachNativeBridge(view)
            bridgeView = view
        }
        val handshake = session.beginLoad(workspaceName)
        bridge.updateSession(handshake.sessionId, handshake.generation)
        installBootstrap(view, handshake)
        if (!bridgeAttached) {
            session.markFailure("This WebView does not support the required AirDesk bridge APIs.")
        }
        view.loadUrl(startUrl(handshake))
    }

    fun detach() {
        webView = null
        bridgeView = null
        bridgeAttached = false
    }

    override fun sendTerminalReady() {
        sendControl("terminalReady")
        session.markTerminalStatus("Connected to remote terminal")
    }

    override fun sendTerminalData(base64Data: String) {
        sendControl("terminalData", mapOf("data" to base64Data))
    }

    override fun sendTerminalStatus(status: String) {
        sendControl("terminalStatus", mapOf("message" to status))
        session.markTerminalStatus(status)
    }

    override fun sendTerminalExit(message: String) {
        sendControl("terminalExit", mapOf("message" to message))
        session.markTerminalStatus(message)
    }

    fun updateRemoteTerminalProfile(profile: RemoteTerminalProfileDraft, restart: Boolean = false) {
        val configuration = profile.configurationOrNull()
        val enabled = profile.enabled && configuration != null
        remoteTerminalBootstrap = buildJsonObject {
            put("enabled", enabled)
            put("host", configuration?.host ?: profile.host.trim())
            put(
                "username",
                configuration?.username ?: profile.username.trim(),
            )
            put("port", configuration?.port ?: profile.port.toIntOrNull() ?: 22)
            put(
                "startupCommand",
                configuration?.startupCommand ?: profile.startupCommand.trim(),
            )
        }.toString()
        sendControlObject(
            type = "terminalConfig",
            fields = buildJsonObject {
                put("enabled", enabled)
                put("host", configuration?.host ?: profile.host.trim())
                put(
                    "username",
                    configuration?.username ?: profile.username.trim(),
                )
                put("port", configuration?.port ?: profile.port.toIntOrNull() ?: 22)
                put(
                    "startupCommand",
                    configuration?.startupCommand ?: profile.startupCommand.trim(),
                )
                put("revision", System.currentTimeMillis())
                put("restart", restart)
            },
        )
    }

    private fun attachNativeBridge(view: WebView): Boolean {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) ||
            !WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
        ) {
            return false
        }
        return runCatching {
            WebViewCompat.addWebMessageListener(
                view,
                MESSAGE_OBJECT,
                setOf(LOCAL_ORIGIN),
                object : WebViewCompat.WebMessageListener {
                    override fun onPostMessage(
                        webView: WebView,
                        message: WebMessageCompat,
                        sourceOrigin: Uri,
                        isMainFrame: Boolean,
                        replyProxy: JavaScriptReplyProxy,
                    ) {
                        if (!isLocalOrigin(sourceOrigin)) {
                            session.markBridgeRejection("origin", "rejected")
                            return
                        }
                        if (!isMainFrame || message.type != WebMessageCompat.TYPE_STRING) return
                        val data = message.data ?: return
                        receiveWrapper(data)
                    }
                },
            )
            true
        }.getOrDefault(false)
    }

    private fun receiveWrapper(payload: String) {
        if (payload.length > AndroidDesktopBridge.MAXIMUM_PAYLOAD_LENGTH) {
            session.markBridgeRejection("wrapper", AndroidBridgeRejection.MESSAGE_TOO_LARGE.wire)
            return
        }
        val root = runCatching { json.parseToJsonElement(payload) as? JsonObject }.getOrNull()
        if (root == null) {
            session.markBridgeRejection("wrapper", AndroidBridgeRejection.MALFORMED_PAYLOAD.wire)
            return
        }
        val kind = (root["kind"] as? JsonPrimitive)?.contentOrNull
        val message = root["payload"] as? JsonObject
        if (kind == null || message == null) {
            session.markBridgeRejection("wrapper", AndroidBridgeRejection.MALFORMED_PAYLOAD.wire)
            return
        }
        when (val result = bridge.receive(kind, message.toString())) {
            is AndroidBridgeReceiveResult.Rejected ->
                session.markBridgeRejection(kind, result.reason.wire)
            is AndroidBridgeReceiveResult.Accepted -> Unit
        }
    }

    private fun handleRuntimeMessage(message: AndroidBridgeMessage) {
        when (message.type) {
            "ready" -> {
                session.markReady(
                    message.width?.let { if (it.isFinite()) it.roundToInt() else null },
                    message.height?.let { if (it.isFinite()) it.roundToInt() else null },
                )
            }
            "viewport" -> {
                val width = message.width
                val height = message.height
                if (width != null && height != null && width.isFinite() && height.isFinite()) {
                    session.markViewport(width.roundToInt(), height.roundToInt())
                }
            }
            "state" -> message.message?.let(session::markRuntimeState)
            "error" -> message.message?.let(session::markRuntimeError)
            "notice" -> session.markRuntimeState("notice")
            "action" -> message.action?.let { session.markRuntimeState("action:$it") }
            "ack", "log" -> Unit
        }
    }

    private fun handleTerminalMessage(message: AndroidTerminalMessage) {
        val handler = terminalHandler
        if (handler == null) {
            if (message.action == "start") {
                sendTerminalExit("Remote terminal service is not connected yet.")
            }
            return
        }
        when (message.action) {
            "start" -> {
                session.markTerminalStatus("Starting remote terminal")
                runCatching { handler(message) }
                    .onFailure { session.markTerminalStatus("Remote terminal start failed") }
            }
            "write", "resize" -> runCatching { handler(message) }
            "stop" -> {
                runCatching { handler(message) }
                session.markTerminalStatus("Remote terminal stopped")
            }
        }
    }

    private fun sendControl(type: String, fields: Map<String, String?> = emptyMap()) {
        val view = webView ?: return
        val message = AndroidDesktopBridge.encodeControl(
            sessionId = session.sessionId,
            generation = session.currentGeneration,
            type = type,
            fields = fields,
        )
        evaluateControl(view, message)
    }

    private fun sendControlObject(type: String, fields: JsonObject) {
        val view = webView ?: return
        val message = buildJsonObject {
            put("version", AndroidDesktopBridge.VERSION)
            put("type", type)
            put("sessionId", session.sessionId)
            put("generation", session.currentGeneration)
            fields.forEach { (key, value) -> put(key, value) }
        }.toString()
        evaluateControl(view, message)
    }

    private fun evaluateControl(view: WebView, message: String) {
        val script = """
            if (window.AirDeskBridge && typeof window.AirDeskBridge.receiveControl === 'function') {
                window.AirDeskBridge.receiveControl($message);
                true;
            } else {
                false;
            }
        """.trimIndent()
        view.post { view.evaluateJavascript(script, null) }
    }

    private fun installBootstrap(view: WebView, handshake: DisplaySessionHandshake) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) return
        runCatching {
            WebViewCompat.addDocumentStartJavaScript(
                view,
                bootstrapScript(handshake),
                setOf(LOCAL_ORIGIN),
            )
        }.onFailure {
            session.markFailure("The AirDesk bootstrap script could not be installed.")
        }
    }

    private fun bootstrapScript(handshake: DisplaySessionHandshake): String = """
        (function () {
          window.AIRDESK_SESSION_ID = ${jsString(handshake.sessionId)};
          window.AIRDESK_GENERATION = ${handshake.generation};
          window.AIRDESK_RUNTIME = "wanixDesktop";
          window.AIRDESK_APPEARANCE = "dark";
          window.AIRDESK_DEVICE_NAME = ${jsString(deviceName)};
          window.AIRDESK_REMOTE_TERMINAL = $remoteTerminalBootstrap;
          var host = window.AirDeskAndroidHost;
          if (!host || typeof host.postMessage !== 'function') return;
          var webkit = window.webkit || (window.webkit = {});
          var handlers = webkit.messageHandlers || (webkit.messageHandlers = {});
          function install(name, kind) {
            if (handlers[name]) return;
            handlers[name] = {
              postMessage: function (message) {
                try {
                  host.postMessage(JSON.stringify({ kind: kind, payload: message }));
                } catch (error) {
                }
              }
            };
          }
          install("airdesk", "runtime");
          install("airdeskTerminal", "terminal");
        })();
    """.trimIndent()

    private fun startUrl(handshake: DisplaySessionHandshake): String =
        Uri.Builder()
            .scheme("https")
            .authority(ASSET_DOMAIN)
            .path(ASSET_PREFIX + "index.html")
            .appendQueryParameter("session", handshake.sessionId)
            .appendQueryParameter("generation", handshake.generation.toString())
            .appendQueryParameter("runtime", "wanixDesktop")
            .appendQueryParameter("appearance", "dark")
            .appendQueryParameter("device", deviceName)
            .build()
            .toString()

    private fun isLocalOrigin(origin: Uri): Boolean =
        origin.scheme == "https" && origin.host == ASSET_DOMAIN

    private fun jsString(value: String): String = JsonPrimitive(value).toString()

    companion object {
        const val ASSET_DOMAIN = "appassets.androidplatform.net"
        const val ASSET_PREFIX = "/assets/DesktopShell/"
        const val LOCAL_ORIGIN = "https://$ASSET_DOMAIN"
        const val START_URL = "$LOCAL_ORIGIN${ASSET_PREFIX}index.html"
        const val MESSAGE_OBJECT = "AirDeskAndroidHost"
    }
}
