package com.airdesk.android.input

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged

@Composable
fun AndroidTrackpadSurface(
    router: AndroidInputRouter,
    modifier: Modifier = Modifier,
) {
    var cursor by remember { mutableStateOf(Offset(0.5f, 0.5f)) }
    var active by remember { mutableStateOf(false) }

    LaunchedEffect(router) {
        while (true) {
            withFrameNanos { frameTimeNanos ->
                router.tick(frameTimeNanos)
                cursor = Offset(router.cursorX.toFloat(), router.cursorY.toFloat())
                active = router.isActive
            }
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .onSizeChanged {
                router.setViewport(it.width.toDouble(), it.height.toDouble())
            }
            .pointerInput(router) {
                awaitPointerEventScope {
                    var tracking = false
                    var last = Offset.Zero
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull() ?: continue
                        if (!change.pressed) {
                            tracking = false
                            continue
                        }
                        if (!tracking) {
                            tracking = true
                            last = change.position
                            change.consume()
                            continue
                        }
                        val delta = change.position - last
                        last = change.position
                        if (delta != Offset.Zero) {
                            router.submitMove(delta.x.toDouble(), delta.y.toDouble())
                            change.consume()
                        }
                    }
                }
            },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            if (!active) return@Canvas
            val center = Offset(cursor.x * size.width, cursor.y * size.height)
            drawCircle(
                color = Color.Black.copy(alpha = 0.55f),
                radius = 8f,
                center = center + Offset(0f, 1f),
            )
            drawCircle(
                color = Color.White.copy(alpha = 0.92f),
                radius = 5f,
                center = center,
            )
            drawCircle(
                color = Color(0f, 0.72f, 0.64f, 0.95f),
                radius = 5f,
                center = center,
                style = androidx.compose.ui.graphics.drawscope.Stroke(width = 2f),
            )
        }
    }
}
