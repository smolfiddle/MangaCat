package ph.smolfiddle.mangacat

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.OutputStream

/**
 * Storage Access Framework gateway.
 *
 * All file access happens through user-picked SAF URIs with persistable
 * permissions. The app declares no storage or INTERNET permission.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "mangacat/saf"
    private val requestOpenFile = 4101
    private val requestOpenTree = 4102
    private val requestCreateFile = 4103

    private var pendingResult: MethodChannel.Result? = null
    private var pendingRequest: Int = 0

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> onMethodCall(call, result) }
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFile" -> launchPicker(
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                },
                requestOpenFile,
                result,
            )
            "pickDirectory" -> launchPicker(
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                    )
                },
                requestOpenTree,
                result,
            )
            "createFile" -> {
                val name = call.argument<String>("suggestedName") ?: "MangaCat.csv"
                val mime = call.argument<String>("mimeType") ?: "text/csv"
                launchPicker(
                    Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = mime
                        putExtra(Intent.EXTRA_TITLE, name)
                    },
                    requestCreateFile,
                    result,
                )
            }
            "readBytes" -> runSaf(result) {
                val uri = call.argument<String>("uri")!!
                val bytes = contentResolver.openInputStream(Uri.parse(uri))?.use { it.readBytes() }
                    ?: throw IllegalStateException("Could not open $uri")
                mapOf("bytes" to Base64.encodeToString(bytes, Base64.NO_WRAP))
            }
            "writeBytes" -> runSaf(result) {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                val bytes = Base64.decode(call.argument<String>("bytes")!!, Base64.NO_WRAP)
                writeTruncating(uri, bytes)
                describe(uri)
            }
            "stat" -> runSaf(result) { describe(Uri.parse(call.argument<String>("uri")!!)) }
            "listChildren" -> runSaf(result) {
                listChildren(Uri.parse(call.argument<String>("uri")!!))
            }
            "checkPersisted" -> runSaf(result) {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                mapOf("persisted" to isPersisted(uri))
            }
            "releasePermission" -> runSaf(result) {
                releasePersisted(Uri.parse(call.argument<String>("uri")!!))
                true
            }
            else -> result.notImplemented()
        }
    }

    private fun launchPicker(intent: Intent, request: Int, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "Another picker is already open", null)
            return
        }
        pendingResult = result
        pendingRequest = request
        try {
            startActivityForResult(intent, request)
        } catch (e: Exception) {
            pendingResult = null
            result.error("unavailable", e.message, null)
        }
    }

    @Deprecated("Handled manually to keep a single pending picker result.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pendingRequest) return
        val result = pendingResult ?: return
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }
        val uri = data.data!!
        val flags = data.flags and (
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        try {
            if (flags != 0) {
                contentResolver.takePersistableUriPermission(uri, flags)
            }
        } catch (_: SecurityException) {
            // Some providers refuse persistable grants; the session grant still works.
        }
        try {
            result.success(describe(uri))
        } catch (e: Exception) {
            result.error("io", e.message, null)
        }
    }

    private fun describe(uri: Uri): Map<String, Any?> {
        var name: String? = null
        var size: Long = -1
        var mtime: Long = -1
        try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    name = stringOrNull(cursor, OpenableColumns.DISPLAY_NAME)
                    val idxSize = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (idxSize >= 0 && !cursor.isNull(idxSize)) size = cursor.getLong(idxSize)
                    val idxModified =
                        cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                    if (idxModified >= 0 && !cursor.isNull(idxModified)) {
                        mtime = cursor.getLong(idxModified)
                    }
                }
            }
        } catch (_: Exception) {
            // Fall through: a missing document reports exists=false below.
        }
        if (name == null) {
            val exists = try {
                contentResolver.openInputStream(uri)?.use { true } ?: false
            } catch (_: Exception) {
                false
            }
            return mapOf(
                "uri" to uri.toString(),
                "name" to uri.lastPathSegment,
                "size" to size,
                "mtime" to mtime,
                "exists" to exists,
            )
        }
        return mapOf(
            "uri" to uri.toString(),
            "name" to name,
            "size" to size,
            "mtime" to mtime,
            "exists" to true,
        )
    }

    private fun stringOrNull(cursor: Cursor, column: String): String? {
        val index = cursor.getColumnIndex(column)
        return if (index >= 0 && !cursor.isNull(index)) cursor.getString(index) else null
    }

    private fun listChildren(treeUri: Uri): List<Map<String, Any?>> {
        val childrenUri = if (DocumentsContract.isTreeUri(treeUri)) {
            DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri),
            )
        } else {
            DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getDocumentId(treeUri),
            )
        }
        val out = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                DocumentsContract.Document.COLUMN_SIZE,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val docId = cursor.getString(0) ?: continue
                val name = cursor.getString(1) ?: continue
                val mime = cursor.getString(2) ?: ""
                val mtime = if (cursor.isNull(3)) -1L else cursor.getLong(3)
                val size = if (cursor.isNull(4)) -1L else cursor.getLong(4)
                val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                out.add(
                    mapOf(
                        "uri" to childUri.toString(),
                        "name" to name,
                        "isDirectory" to (mime == DocumentsContract.Document.MIME_TYPE_DIR),
                        "mtime" to mtime,
                        "size" to size,
                    ),
                )
            }
        }
        return out
    }

    private fun writeTruncating(uri: Uri, bytes: ByteArray) {
        var stream: OutputStream? = null
        var openedTruncating = false
        try {
            stream = contentResolver.openOutputStream(uri, "wt")
            openedTruncating = true
        } catch (_: Exception) {
            stream = contentResolver.openOutputStream(uri, "w")
        }
        stream?.use { it.write(bytes); it.flush() }
            ?: throw IllegalStateException("Could not open $uri for writing")
        if (!openedTruncating) {
            try {
                contentResolver.openFileDescriptor(uri, "rw")?.use { pfd ->
                    FileOutputStream(pfd.fileDescriptor).use { fos ->
                        fos.channel.truncate(bytes.size.toLong())
                    }
                }
            } catch (_: Exception) {
                // Best effort; most providers support "wt" directly.
            }
        }
    }

    private fun isPersisted(uri: Uri): Boolean =
        contentResolver.persistedUriPermissions.any {
            it.uri == uri && (it.isReadPermission || it.isWritePermission)
        }

    private fun releasePersisted(uri: Uri) {
        try {
            contentResolver.releasePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            // Nothing to release.
        }
    }

    private fun runSaf(result: MethodChannel.Result, block: () -> Any?) {
        try {
            result.success(block())
        } catch (e: SecurityException) {
            result.error("permission", e.message, null)
        } catch (e: Exception) {
            result.error("io", e.message, null)
        }
    }
}
