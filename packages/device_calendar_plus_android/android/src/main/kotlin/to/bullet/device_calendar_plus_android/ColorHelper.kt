package to.bullet.device_calendar_plus_android

import android.graphics.Color

object ColorHelper {
    fun hexToColor(hex: String): Int {
        val hexSanitized = hex.trim().removePrefix("#")
        
        // Parse RGB hex string to integer
        return try {
            Color.parseColor("#$hexSanitized")
        } catch (e: Exception) {
            // Default to black if parsing fails
            Color.BLACK
        }
    }
    
    fun colorToHex(color: Int): String {
        // Android color is ARGB, we want RGB hex string
        return String.format("#%06X", 0xFFFFFF and color)
    }
}

