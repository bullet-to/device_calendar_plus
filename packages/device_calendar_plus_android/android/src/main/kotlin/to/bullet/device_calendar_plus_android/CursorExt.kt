package to.bullet.device_calendar_plus_android

import android.content.ContentValues
import android.database.Cursor

/** The current row's [column] as a Long, or null when it is NULL. */
internal fun Cursor.longOrNull(column: String): Long? {
    val index = getColumnIndexOrThrow(column)
    return if (isNull(index)) null else getLong(index)
}

/** The current row's [column] as a String, or null when it is NULL. */
internal fun Cursor.stringOrNull(column: String): String? {
    val index = getColumnIndexOrThrow(column)
    return if (isNull(index)) null else getString(index)
}

/**
 * Puts the current row's value of each of [columns] into [values], by
 * name and with its stored type, nulls included.
 */
internal fun Cursor.copyColumnsInto(values: ContentValues, columns: Array<String>) {
    for (column in columns) {
        val index = getColumnIndexOrThrow(column)
        when (getType(index)) {
            Cursor.FIELD_TYPE_NULL -> values.putNull(column)
            Cursor.FIELD_TYPE_INTEGER -> values.put(column, getLong(index))
            Cursor.FIELD_TYPE_FLOAT -> values.put(column, getDouble(index))
            Cursor.FIELD_TYPE_BLOB -> values.put(column, getBlob(index))
            else -> values.put(column, getString(index))
        }
    }
}
