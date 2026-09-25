package to.bullet.device_calendar_plus_android

import android.graphics.Color

object ColorHelper {
    /** [hex] is the canonical `#RRGGBB` Dart's `normalizeColorHex` forwards. */
    fun hexToColor(hex: String): Int = Color.parseColor(hex)

    fun colorToHex(color: Int): String {
        // Android color is ARGB, we want RGB hex string
        return String.format("#%06X", 0xFFFFFF and color)
    }
}

