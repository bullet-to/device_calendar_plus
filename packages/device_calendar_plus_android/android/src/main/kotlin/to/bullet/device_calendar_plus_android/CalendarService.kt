package to.bullet.device_calendar_plus_android

import android.content.Context
import android.net.Uri
import android.provider.CalendarContract

class CalendarService(private val context: Context) {

    fun listCalendars(): Result<List<Map<String, Any>>> {
        readAccessFailure(context)?.let { return Result.failure(it) }

        val calendars = mutableListOf<Map<String, Any>>()
        
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.CALENDAR_COLOR,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.ACCOUNT_TYPE,
            CalendarContract.Calendars.IS_PRIMARY,
            CalendarContract.Calendars.VISIBLE
        )
        
        try {
            context.contentResolver.query(
                CalendarContract.Calendars.CONTENT_URI,
                projection,
                null,
                null,
                null
            )?.use { cursor ->
                val idIndex = cursor.getColumnIndex(CalendarContract.Calendars._ID)
                val nameIndex = cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME)
                val colorIndex = cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_COLOR)
                val accessLevelIndex = cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL)
                val accountNameIndex = cursor.getColumnIndex(CalendarContract.Calendars.ACCOUNT_NAME)
                val accountTypeIndex = cursor.getColumnIndex(CalendarContract.Calendars.ACCOUNT_TYPE)
                val isPrimaryIndex = cursor.getColumnIndex(CalendarContract.Calendars.IS_PRIMARY)
                val visibleIndex = cursor.getColumnIndex(CalendarContract.Calendars.VISIBLE)
                
                while (cursor.moveToNext()) {
                    // Exotic provider rows can carry NULLs here; Dart casts both
                    // with `as String`, so a row without an id is unusable and a
                    // missing display name reads as empty (#126).
                    val id = cursor.getString(idIndex) ?: continue
                    val name = cursor.getString(nameIndex) ?: ""
                    val color = if (!cursor.isNull(colorIndex)) cursor.getInt(colorIndex) else null
                    val accessLevel = cursor.getInt(accessLevelIndex)
                    val accountName = if (!cursor.isNull(accountNameIndex)) cursor.getString(accountNameIndex) else null
                    val accountType = if (!cursor.isNull(accountTypeIndex)) cursor.getString(accountTypeIndex) else null
                    val isPrimary = if (!cursor.isNull(isPrimaryIndex)) cursor.getInt(isPrimaryIndex) == 1 else false
                    val visible = if (!cursor.isNull(visibleIndex)) cursor.getInt(visibleIndex) == 1 else true
                    
                    val readOnly = isReadOnly(accessLevel)
                    
                    // Convert color to hex string
                    val colorHex = color?.let { ColorHelper.colorToHex(it) }
                    
                    val calendarMap = mutableMapOf<String, Any>(
                        "id" to id,
                        "name" to name,
                        "readOnly" to readOnly,
                        "isPrimary" to isPrimary,
                        "hidden" to !visible // Invert visible to hidden
                    )
                    
                    colorHex?.let { calendarMap["colorHex"] = it }
                    accountName?.let { calendarMap["accountName"] = it }
                    accountType?.let { calendarMap["accountType"] = it }
                    
                    calendars.add(calendarMap)
                }
            }
        } catch (e: SecurityException) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied: ${e.message}"
                )
            )
        } catch (e: Exception) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.UNKNOWN_ERROR,
                    "Failed to query calendars: ${e.message}"
                )
            )
        }
        
        return Result.success(calendars)
    }

    /**
     * Resolves the id of a calendar to write new events into when the caller
     * omits one. Prefers the primary writable calendar; otherwise falls back to
     * the first writable calendar. `success(null)` means no writable calendar
     * exists; `failure(permissionDenied)` means we couldn't read the calendar
     * list to pick one. The two are distinct so the caller surfaces an honest
     * error instead of reporting "no calendar" for a missing READ_CALENDAR.
     *
     * Reuses [listCalendars] so the writability definition stays in one place.
     */
    fun resolveDefaultWritableCalendarId(): Result<String?> {
        // Picking a default reads the calendar list; listCalendars gates the
        // read itself, and its failure propagates through the map.
        return listCalendars().map { calendars ->
            val writable = calendars.filter { it["readOnly"] == false }
            (writable.firstOrNull { it["isPrimary"] == true } ?: writable.firstOrNull())
                ?.get("id") as? String
        }
    }

    fun listSources(): Result<List<Map<String, Any>>> {
        readAccessFailure(context)?.let { return Result.failure(it) }

        val sources = mutableListOf<Map<String, Any>>()
        val seen = mutableSetOf<String>()

        try {
            context.contentResolver.query(
                CalendarContract.Calendars.CONTENT_URI,
                arrayOf(
                    CalendarContract.Calendars.ACCOUNT_NAME,
                    CalendarContract.Calendars.ACCOUNT_TYPE,
                ),
                null, null, null
            )?.use { cursor ->
                val nameIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_NAME)
                val typeIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_TYPE)

                while (cursor.moveToNext()) {
                    val accountName = cursor.getString(nameIdx) ?: continue
                    val accountType = cursor.getString(typeIdx) ?: continue
                    val key = "${Uri.encode(accountName)}:${Uri.encode(accountType)}"

                    if (seen.add(key)) {
                        sources.add(mapOf(
                            "id" to key,
                            "accountName" to accountName,
                            "accountType" to accountType,
                            "type" to accountTypeToSourceType(accountType),
                            "supportsCalendarCreation" to supportsCalendarCreation(accountType),
                        ))
                    }
                }
            }
        } catch (e: SecurityException) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied: ${e.message}"
                )
            )
        }

        return Result.success(sources)
    }

    /**
     * Only the local account type can hold a calendar this app creates. Every
     * other type belongs to a sync adapter, and a calendar inserted into its
     * namespace behind its back is one it can wipe on the next sync. One
     * definition, so what listSources reports is what createCalendar enforces.
     */
    private fun supportsCalendarCreation(accountType: String): Boolean =
        accountType == CalendarContract.ACCOUNT_TYPE_LOCAL

    /**
     * The readOnly definition listCalendars reports. The mutations use the
     * same one, so a calendar the list calls writable is one they accept —
     * the contract iOS gets from a single EventKit flag.
     */
    private fun isReadOnly(accessLevel: Int): Boolean =
        accessLevel < CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR

    /**
     * The refusal for a calendar the app can't rename, recolor or delete,
     * decided before any write. The provider has no immutable flag and would
     * update or delete any row it's handed, so this is where the readOnly the
     * API documents comes from on Android (#126). `null` means go ahead.
     */
    private fun writeRefusal(calendarId: String): CalendarException? {
        val accessLevel = context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL),
            "${CalendarContract.Calendars._ID} = ?",
            arrayOf(calendarId),
            null
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val index = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL)
            if (cursor.isNull(index)) CalendarContract.Calendars.CAL_ACCESS_NONE else cursor.getInt(index)
        } ?: return CalendarException(
            PlatformExceptionCodes.NOT_FOUND,
            "Calendar with ID $calendarId not found"
        )

        if (isReadOnly(accessLevel)) {
            return CalendarException(
                PlatformExceptionCodes.READ_ONLY,
                "Calendar is read-only and cannot be modified or deleted"
            )
        }
        return null
    }

    private fun accountTypeToSourceType(accountType: String): String {
        return when (accountType) {
            CalendarContract.ACCOUNT_TYPE_LOCAL -> "local"
            "com.google" -> "calDav"
            "com.android.exchange" -> "exchange"
            "com.samsung.android.exchange" -> "exchange"
            else -> "other"
        }
    }

    fun createCalendar(name: String, colorHex: String?, accountNameParam: String?, accountTypeParam: String?): Result<String> {
        fullAccessFailure(context)?.let { return Result.failure(it) }

        val accountName = accountNameParam ?: "local"
        val accountType = accountTypeParam ?: CalendarContract.ACCOUNT_TYPE_LOCAL

        // Refuse what listSources reports as non-creatable, the way iOS refuses
        // a non-iCloud/local source, instead of leaving a phantom calendar in
        // a sync adapter's namespace.
        if (!supportsCalendarCreation(accountType)) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.READ_ONLY,
                    "Account type '$accountType' does not allow calendars to be created. " +
                        "Use the local account type (a source listSources reports " +
                        "supportsCalendarCreation for)."
                )
            )
        }
        
        // Android automatically creates the account when inserting the first calendar
        try {
            val values = android.content.ContentValues().apply {
                put(CalendarContract.Calendars.ACCOUNT_NAME, accountName)
                put(CalendarContract.Calendars.ACCOUNT_TYPE, accountType)
                put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, name)
                put(CalendarContract.Calendars.NAME, name)
                put(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.CAL_ACCESS_OWNER)
                put(CalendarContract.Calendars.OWNER_ACCOUNT, accountName)
                put(CalendarContract.Calendars.VISIBLE, 1)
                put(CalendarContract.Calendars.SYNC_EVENTS, 1)
                
                // Set color if provided
                if (colorHex != null) {
                    val color = ColorHelper.hexToColor(colorHex)
                    put(CalendarContract.Calendars.CALENDAR_COLOR, color)
                }
            }
            
            val uri = context.contentResolver.insert(
                CalendarContract.Calendars.CONTENT_URI
                    .buildUpon()
                    .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
                    .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, accountName)
                    .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, accountType)
                    .build(),
                values
            )
            
            if (uri != null) {
                val calendarId = uri.lastPathSegment
                if (calendarId != null) {
                    return Result.success(calendarId)
                }
            }
            
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to create calendar: No calendar ID returned"
                )
            )
        } catch (e: SecurityException) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied: ${e.message}"
                )
            )
        } catch (e: Exception) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to create calendar: ${e.message}"
                )
            )
        }
    }
    
    fun updateCalendar(calendarId: String, name: String?, colorHex: String?): Result<Unit> {
        fullAccessFailure(context)?.let { return Result.failure(it) }

        try {
            writeRefusal(calendarId)?.let { return Result.failure(it) }

            // Prepare values to update
            val values = android.content.ContentValues()
            
            // Update name if provided
            if (name != null) {
                values.put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, name)
                values.put(CalendarContract.Calendars.NAME, name)
            }
            
            // Update color if provided
            if (colorHex != null) {
                val color = ColorHelper.hexToColor(colorHex)
                values.put(CalendarContract.Calendars.CALENDAR_COLOR, color)
            }
            
            // Update the calendar
            val updatedRows = context.contentResolver.update(
                CalendarContract.Calendars.CONTENT_URI,
                values,
                "${CalendarContract.Calendars._ID} = ?",
                arrayOf(calendarId)
            )
            
            if (updatedRows == 0) {
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.NOT_FOUND,
                        "Calendar with ID $calendarId not found"
                    )
                )
            }
            
            return Result.success(Unit)
        } catch (e: SecurityException) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied: ${e.message}"
                )
            )
        } catch (e: Exception) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to update calendar: ${e.message}"
                )
            )
        }
    }
    
    fun deleteCalendar(calendarId: String): Result<Unit> {
        fullAccessFailure(context)?.let { return Result.failure(it) }

        try {
            writeRefusal(calendarId)?.let { return Result.failure(it) }

            val deletedRows = context.contentResolver.delete(
                CalendarContract.Calendars.CONTENT_URI,
                "${CalendarContract.Calendars._ID} = ?",
                arrayOf(calendarId)
            )
            
            if (deletedRows == 0) {
                return Result.failure(
                    CalendarException(
                        PlatformExceptionCodes.NOT_FOUND,
                        "Calendar with ID $calendarId not found"
                    )
                )
            }
            
            return Result.success(Unit)
        } catch (e: SecurityException) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.PERMISSION_DENIED,
                    "Calendar permission denied: ${e.message}"
                )
            )
        } catch (e: Exception) {
            return Result.failure(
                CalendarException(
                    PlatformExceptionCodes.OPERATION_FAILED,
                    "Failed to delete calendar: ${e.message}"
                )
            )
        }
    }
    
}

data class CalendarException(
    val code: String,
    override val message: String
) : Exception(message)

