package com.airdesk.android.remote

import com.airdesk.android.workspace.AndroidTerminalMessage
import java.util.Base64
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteSSHTest {
    private val hostKey = "ssh-ed25519 AAAA"

    @Test
    fun pinnedHostKeyParsesSupportedOpenSSHKeysAndRejectsMalformedValues() {
        val parsed = PinnedHostKey.parse("  ssh-ed25519 AAAA comment")
        assertEquals("ssh-ed25519", parsed.algorithm)
        assertEquals("AAAA", parsed.base64)

        val unsupported = assertThrows(RemoteSSHException::class.java) {
            PinnedHostKey.parse("ssh-dss AAAA")
        }
        assertEquals(RemoteSSHErrorCode.INVALID_HOST_KEY, unsupported.code)

        val malformed = assertThrows(RemoteSSHException::class.java) {
            PinnedHostKey.parse("ssh-ed25519 not-base64!")
        }
        assertEquals(RemoteSSHErrorCode.INVALID_HOST_KEY, malformed.code)
    }

    @Test
    fun configurationNormalizesFieldsAndRejectsInvalidValues() {
        val configuration = configuration().copy(
            host = "  example.test ",
            username = "  operator ",
            startupCommand = "  tmux new -A -s airdesk  ",
        ).validate()

        assertEquals("example.test", configuration.host)
        assertEquals("operator", configuration.username)
        assertEquals("tmux new -A -s airdesk", configuration.startupCommand)

        val invalid = assertThrows(RemoteSSHException::class.java) {
            configuration().copy(port = 0).validate()
        }
        assertEquals(RemoteSSHErrorCode.INVALID_CONFIGURATION, invalid.code)
    }

    @Test
    fun terminalRequiresMatchingLeaseAndReleasesItOnRevocation() {
        val registry = RemoteSSHLeaseRegistry(now = { 1_000L })
        val driver = FakeDriver()
        val terminal = RemoteSSHTerminal(driver, registry)
        val context = context()
        val lease = lease(context = context)
        registry.grant(lease)
        val exits = mutableListOf<RemoteSSHEvent>()

        terminal.start(
            configuration = configuration(),
            size = RemoteSSHSize(100, 40),
            context = context.copy(leaseId = lease.leaseId),
        )
        terminal.onEvent = { event -> exits.add(event) }

        assertTrue(terminal.isRunning)
        assertEquals("example.test", driver.configuration?.host)
        assertEquals(100, driver.size?.columns)

        terminal.write("ls\n".toByteArray())
        terminal.resize(120, 50)
        assertArrayEquals("ls\n".toByteArray(), driver.writes.single())
        assertEquals(120, driver.resizes.single().first)
        val stopsBeforeRevoke = driver.stopCount

        registry.revoke(lease.leaseId)
        terminal.write("whoami\n".toByteArray())

        assertFalse(terminal.isRunning)
        assertEquals(stopsBeforeRevoke + 1, driver.stopCount)
        assertEquals(1, driver.writes.size)
        assertTrue(
            (exits.single() as RemoteSSHEvent.Exit).message.orEmpty().contains("revoked"),
        )
    }

    @Test
    fun missingLeasePreventsStartAndProducesDeniedAudit() {
        val registry = RemoteSSHLeaseRegistry(now = { 1_000L })
        val driver = FakeDriver()
        val terminal = RemoteSSHTerminal(driver, registry)

        val error = assertThrows(RemoteSSHException::class.java) {
            terminal.start(configuration(), RemoteSSHSize(), context())
        }

        assertEquals(RemoteSSHErrorCode.LEASE_DENIED, error.code)
        assertEquals(0, driver.startCount)
        assertEquals(RemoteSSHAuditDecision.DENIED, terminal.auditEvents.single().decision)
    }

    @Test
    fun serviceControllerReattachesWithoutStoppingAndHandsWritesToNewClient() {
        val registry = RemoteSSHLeaseRegistry(now = { 1_000L })
        val driver = FakeDriver()
        val terminal = RemoteSSHTerminal(driver, registry)
        val service = RemoteSSHServiceController(terminal)
        val context = context()
        val lease = lease(context = context)
        registry.grant(lease)
        val events = mutableListOf<RemoteSSHServiceEvent>()
        service.addEventListener { events.add(it) }

        service.start(
            configuration = configuration(),
            size = RemoteSSHSize(),
            context = context.copy(leaseId = lease.leaseId),
            clientId = "client-a",
        )
        driver.ready()
        assertTrue(service.snapshot().isRunning)

        service.detach("client-a")
        assertEquals(RemoteSSHServicePhase.RUNNING, service.snapshot().phase)
        assertTrue(service.snapshot().attachedClientIds.isEmpty())
        service.write("ignored".toByteArray(), "client-a")
        assertTrue(driver.writes.isEmpty())

        service.attach("client-b")
        service.write("echo ok\n".toByteArray(), "client-b")
        assertArrayEquals("echo ok\n".toByteArray(), driver.writes.single())

        driver.data("ok\n".toByteArray())
        val event = events.last()
        assertEquals("client-b", event.clientId)
        assertArrayEquals("ok\n".toByteArray(), (event.event as RemoteSSHEvent.Data).bytes)

        service.stop()
        assertEquals(RemoteSSHServicePhase.IDLE, service.snapshot().phase)
    }

    @Test
    fun hostBridgeMapsTerminalProtocolAndBase64Data() {
        val registry = RemoteSSHLeaseRegistry(now = { 1_000L })
        val driver = FakeDriver()
        val terminal = RemoteSSHTerminal(driver, registry)
        val service = RemoteSSHServiceController(terminal)
        val context = context()
        val lease = lease(context = context)
        registry.grant(lease)
        val output = FakeOutput()
        var started = false
        var stopped = false
        val bridge = RemoteSSHHostBridge(
            controller = service,
            output = output,
            configuration = { configuration() },
            context = { context.copy(leaseId = lease.leaseId) },
            size = { RemoteSSHSize(90, 30) },
            clientId = "bridge-client",
        ).apply {
            onStartRequested = { started = true }
            onStopRequested = { stopped = true }
        }
        bridge.attach()

        bridge.handle(AndroidTerminalMessage(action = "start"))
        assertTrue(started)
        assertEquals("Connecting to operator@example.test...", output.statuses.last())

        driver.ready()
        assertTrue(output.ready)
        val startsAfterConnect = driver.startCount
        var startedAgain = false
        bridge.onStartRequested = { startedAgain = true }
        bridge.handle(AndroidTerminalMessage(action = "start"))
        assertFalse(startedAgain)
        assertEquals(startsAfterConnect, driver.startCount)
        assertEquals("Reattached to the running remote terminal", output.statuses.last())

        driver.data("hello\n".toByteArray())
        assertEquals(Base64.getEncoder().encodeToString("hello\n".toByteArray()), output.data.single())

        bridge.handle(
            AndroidTerminalMessage(
                action = "write",
                data = Base64.getEncoder().encodeToString("ls\n".toByteArray()),
            ),
        )
        assertArrayEquals("ls\n".toByteArray(), driver.writes.single())

        bridge.handle(
            AndroidTerminalMessage(
                action = "resize",
                columns = 100,
                rows = 40,
            ),
        )
        assertEquals(100, driver.resizes.single().first)

        driver.exit("Connection closed")
        assertEquals("Connection closed", output.exits.single())

        bridge.handle(AndroidTerminalMessage(action = "stop"))
        assertTrue(stopped)
        bridge.detach()
    }

    @Test
    fun hostBridgeRestartsWhenTheProfileChanges() {
        val registry = RemoteSSHLeaseRegistry(now = { 1_000L })
        val driver = FakeDriver()
        val terminal = RemoteSSHTerminal(driver, registry)
        val service = RemoteSSHServiceController(terminal)
        val context = context()
        val lease = lease(context = context)
        registry.grant(lease)
        var currentConfiguration = configuration()
        val output = FakeOutput()
        val bridge = RemoteSSHHostBridge(
            controller = service,
            output = output,
            configuration = { currentConfiguration },
            context = { context.copy(leaseId = lease.leaseId) },
            clientId = "bridge-client",
        )
        bridge.attach()

        bridge.handle(AndroidTerminalMessage(action = "start"))
        driver.ready()
        assertEquals(1, driver.startCount)

        currentConfiguration = currentConfiguration.copy(host = "new.example.test")
        bridge.handle(AndroidTerminalMessage(action = "start"))

        assertEquals(2, driver.startCount)
        assertEquals("new.example.test", driver.configuration?.host)
        bridge.detach()
    }

    @Test
    fun controllerRunsTransportOffTheCallingThreadAndChunksLargeData() {
        val transport = FakeTransport()
        val controller = RemoteSSHController(transport)
        val events = CopyOnWriteArrayList<RemoteSSHEvent>()
        val ready = CountDownLatch(1)
        controller.onEvent = { event ->
            events.add(event)
            if (event == RemoteSSHEvent.Ready) ready.countDown()
        }

        controller.start(configuration(), RemoteSSHSize())
        assertTrue(ready.await(3, TimeUnit.SECONDS))
        assertTrue(controller.isRunning)

        controller.write("input".toByteArray())
        controller.resize(110, 45)
        assertEquals("input", transport.writes.single())
        assertEquals(110, transport.resizes.single().first)

        val chunks = CountDownLatch(3)
        val before = events.size
        val payload = ByteArray(RemoteSSHController.MAXIMUM_CHUNK_BYTES * 2 + 1) { 7 }
        controller.onEvent = { event ->
            if (event is RemoteSSHEvent.Data) chunks.countDown()
        }
        transport.emitData(payload)
        assertTrue(chunks.await(3, TimeUnit.SECONDS))

        controller.stop()
        assertFalse(controller.isRunning)
        assertEquals(1, transport.closeCount)
        assertTrue(events.size >= before)
    }

    @Test
    fun controllerEmitsReadyBeforeTransportStartData() {
        val transport = FakeTransport().apply {
            dataOnStart = "banner\n".toByteArray()
        }
        val controller = RemoteSSHController(transport)
        val events = CopyOnWriteArrayList<RemoteSSHEvent>()
        val ready = CountDownLatch(1)
        val data = CountDownLatch(1)
        controller.onEvent = { event ->
            events.add(event)
            if (event == RemoteSSHEvent.Ready) ready.countDown()
            if (event is RemoteSSHEvent.Data) data.countDown()
        }

        controller.start(configuration(), RemoteSSHSize())

        assertTrue(ready.await(3, TimeUnit.SECONDS))
        assertTrue(data.await(3, TimeUnit.SECONDS))
        assertTrue(events[0] == RemoteSSHEvent.Ready)
        assertArrayEquals("banner\n".toByteArray(), (events[1] as RemoteSSHEvent.Data).bytes)
        controller.stop()
    }

    @Test
    fun controllerReportsTransportClosureOnce() {
        val transport = FakeTransport()
        val controller = RemoteSSHController(transport)
        val exit = CountDownLatch(1)
        val messages = CopyOnWriteArrayList<String?>()
        controller.onEvent = { event ->
            if (event is RemoteSSHEvent.Exit) {
                messages.add(event.message)
                exit.countDown()
            }
        }
        val ready = CountDownLatch(1)
        val previous = controller.onEvent
        controller.onEvent = { event ->
            previous?.invoke(event)
            if (event == RemoteSSHEvent.Ready) ready.countDown()
        }

        controller.start(configuration(), RemoteSSHSize())
        assertTrue(ready.await(3, TimeUnit.SECONDS))
        transport.emitClosed(RemoteSSHException(RemoteSSHErrorCode.CONNECTION_CLOSED, "Closed"))
        transport.emitClosed(null)

        assertTrue(exit.await(3, TimeUnit.SECONDS))
        Thread.sleep(100)
        assertEquals(1, messages.size)
        assertEquals("Closed", messages.single())
        assertFalse(controller.isRunning)
    }

    private fun configuration(): RemoteSSHConfiguration = RemoteSSHConfiguration(
        host = "example.test",
        port = 2222,
        username = "operator",
        password = "secret",
        hostKey = hostKey,
    )

    private fun context(): RemoteSSHContext = RemoteSSHContext(
        workspaceId = "workspace-a",
        applicationId = "terminal",
        requesterDeviceId = "device-a",
        sessionId = "session-a",
    )

    private fun lease(
        leaseId: String = "lease-1",
        context: RemoteSSHContext = context(),
    ): RemoteSSHLease = RemoteSSHLease(
        leaseId = leaseId,
        capUri = RemoteSSHLeaseRegistry.CAPABILITY_URI,
        workspaceId = context.workspaceId,
        applicationId = context.applicationId,
        requesterDeviceId = context.requesterDeviceId,
        sessionId = context.sessionId,
        issuedAtEpochMillis = 1_000L,
        expiresAtEpochMillis = 10_000L,
        operations = RemoteSSHOperation.entries.toSet(),
        auditId = "audit-$leaseId",
    )

    private class FakeDriver : RemoteSSHDriver {
        override var isRunning = false
            private set
        override var onEvent: ((RemoteSSHEvent) -> Unit)? = null
        var startCount = 0
        var stopCount = 0
        var configuration: RemoteSSHConfiguration? = null
        var size: RemoteSSHSize? = null
        val writes = mutableListOf<ByteArray>()
        val resizes = mutableListOf<Pair<Int, Int>>()

        override fun start(configuration: RemoteSSHConfiguration, size: RemoteSSHSize) {
            startCount += 1
            this.configuration = configuration
            this.size = size
            isRunning = true
        }

        override fun write(data: ByteArray) {
            writes.add(data)
        }

        override fun resize(columns: Int, rows: Int) {
            resizes.add(columns to rows)
        }

        override fun stop() {
            stopCount += 1
            isRunning = false
        }

        fun ready() {
            onEvent?.invoke(RemoteSSHEvent.Ready)
        }

        fun data(bytes: ByteArray) {
            onEvent?.invoke(RemoteSSHEvent.Data(bytes))
        }

        fun exit(message: String?) {
            isRunning = false
            onEvent?.invoke(RemoteSSHEvent.Exit(message))
        }
    }

    private class FakeOutput : RemoteSSHHostOutput {
        var ready = false
        val data = mutableListOf<String>()
        val statuses = mutableListOf<String>()
        val exits = mutableListOf<String>()

        override fun sendTerminalReady() {
            ready = true
        }

        override fun sendTerminalData(base64Data: String) {
            data.add(base64Data)
        }

        override fun sendTerminalStatus(status: String) {
            statuses.add(status)
        }

        override fun sendTerminalExit(message: String) {
            exits.add(message)
        }
    }

    private class FakeTransport : RemoteSSHTransport {
        private var onData: ((ByteArray) -> Unit)? = null
        private var onClosed: ((Throwable?) -> Unit)? = null
        var opened = false
        var closeCount = 0
        var dataOnStart: ByteArray? = null
        val writes = mutableListOf<String>()
        val resizes = mutableListOf<Pair<Int, Int>>()

        override fun open(
            configuration: RemoteSSHConfiguration,
            size: RemoteSSHSize,
            onData: (ByteArray) -> Unit,
            onClosed: (Throwable?) -> Unit,
        ): RemoteSSHConnection {
            opened = true
            this.onData = onData
            this.onClosed = onClosed
            return object : RemoteSSHConnection {
                override fun start() {
                    dataOnStart?.let { data ->
                        this@FakeTransport.onData?.invoke(data)
                    }
                }

                override fun write(data: ByteArray) {
                    writes.add(String(data))
                }

                override fun resize(columns: Int, rows: Int) {
                    resizes.add(columns to rows)
                }

                override fun close() {
                    closeCount += 1
                }
            }
        }

        fun emitData(bytes: ByteArray) {
            assertNotNull(opened)
            onData?.invoke(bytes)
        }

        fun emitClosed(error: Throwable?) {
            onClosed?.invoke(error)
        }
    }
}
