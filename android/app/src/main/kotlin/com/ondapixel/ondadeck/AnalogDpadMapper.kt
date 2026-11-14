package com.ondapixel.ondadeck

import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import kotlin.math.abs

/**
 * Translates left-stick analog and HAT D-Pad [MotionEvent]s into synthetic
 * `KEYCODE_DPAD_*` [KeyEvent]s with deadzone + hysteresis, so Flutter's native
 * `FocusNode` directional traversal works uniformly across all Android controllers.
 */
class AnalogDpadMapper(
    private val dispatchKey: (KeyEvent) -> Boolean,
) {
    companion object {
        private const val PRESS_THRESHOLD = 0.45f
        private const val RELEASE_THRESHOLD = 0.25f
    }

    private var activeHorizontalKey: Int? = null
    private var activeVerticalKey: Int? = null

    fun onGenericMotionEvent(event: MotionEvent): Boolean {
        val isJoystick = (event.source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
        val isGamepad = (event.source and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD
        if (!isJoystick && !isGamepad) return false
        if (event.action != MotionEvent.ACTION_MOVE) return false

        val hatX = getCenteredAxis(event, MotionEvent.AXIS_HAT_X)
        val hatY = getCenteredAxis(event, MotionEvent.AXIS_HAT_Y)
        val stickX = getCenteredAxis(event, MotionEvent.AXIS_X)
        val stickY = getCenteredAxis(event, MotionEvent.AXIS_Y)

        val x = if (abs(hatX) > 0.1f) hatX else stickX
        val y = if (abs(hatY) > 0.1f) hatY else stickY

        val hHandled = updateAxis(
            value = x,
            negativeKey = KeyEvent.KEYCODE_DPAD_LEFT,
            positiveKey = KeyEvent.KEYCODE_DPAD_RIGHT,
            currentKey = activeHorizontalKey,
            deviceId = event.deviceId,
            onUpdate = { activeHorizontalKey = it },
        )
        val vHandled = updateAxis(
            value = y,
            negativeKey = KeyEvent.KEYCODE_DPAD_UP,
            positiveKey = KeyEvent.KEYCODE_DPAD_DOWN,
            currentKey = activeVerticalKey,
            deviceId = event.deviceId,
            onUpdate = { activeVerticalKey = it },
        )

        return hHandled || vHandled || activeHorizontalKey != null || activeVerticalKey != null
    }

    private fun updateAxis(
        value: Float,
        negativeKey: Int,
        positiveKey: Int,
        currentKey: Int?,
        deviceId: Int,
        onUpdate: (Int?) -> Unit,
    ): Boolean {
        val desiredKey: Int? = when {
            value <= -PRESS_THRESHOLD -> negativeKey
            value >= PRESS_THRESHOLD -> positiveKey
            currentKey != null && abs(value) >= RELEASE_THRESHOLD -> currentKey
            else -> null
        }

        if (desiredKey == currentKey) return false

        val now = SystemClock.uptimeMillis()
        if (currentKey != null) {
            emitKey(now, KeyEvent.ACTION_UP, currentKey, deviceId)
        }
        if (desiredKey != null) {
            emitKey(now, KeyEvent.ACTION_DOWN, desiredKey, deviceId)
        }
        onUpdate(desiredKey)
        return true
    }

    private fun emitKey(time: Long, action: Int, keyCode: Int, deviceId: Int) {
        val event = KeyEvent(
            time,
            time,
            action,
            keyCode,
            0,
            0,
            deviceId,
            0,
            KeyEvent.FLAG_FROM_SYSTEM,
            InputDevice.SOURCE_DPAD,
        )
        dispatchKey(event)
    }

    private fun getCenteredAxis(event: MotionEvent, axis: Int): Float {
        val device = event.device
        val range = device?.getMotionRange(axis, event.source)
        val value = event.getAxisValue(axis)
        val flat = range?.flat ?: 0.1f
        return if (abs(value) > flat) value else 0f
    }
}
