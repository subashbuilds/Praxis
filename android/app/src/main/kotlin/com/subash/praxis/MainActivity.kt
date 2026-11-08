package com.subash.praxis

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private companion object {
        const val PICK_IMPORT_FOLDER = 4711
    }

    private var pendingFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "praxis/native",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                "pickImportFolder" -> {
                    if (pendingFolderResult != null) {
                        result.error("picker_busy", "A folder picker is already open.", null)
                    } else {
                        pendingFolderResult = result
                        startActivityForResult(
                            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            },
                            PICK_IMPORT_FOLDER,
                        )
                    }
                }
                "clearImportCache" -> {
                    File(cacheDir, "imports").deleteRecursively()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_IMPORT_FOLDER) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val pending = pendingFolderResult
        pendingFolderResult = null
        if (pending == null) return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(null)
            return
        }
        Thread {
            try {
                val path = copyTree(uri)
                runOnUiThread { pending.success(path) }
            } catch (error: Exception) {
                runOnUiThread {
                    pending.error(
                        "import_folder",
                        error.message ?: "The selected folder could not be read.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun copyTree(uri: Uri): String {
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            // Some providers grant only a temporary read. Copying still works.
        }
        val rootId = DocumentsContract.getTreeDocumentId(uri)
        val rootUri = DocumentsContract.buildDocumentUriUsingTree(uri, rootId)
        val folderName = queryName(rootUri).ifBlank { "Imported folder" }
        val container = File(cacheDir, "imports/${System.currentTimeMillis()}")
        if (container.exists()) container.deleteRecursively()
        container.mkdirs()
        val destination = File(container, safeName(folderName))
        copyDocument(uri, rootUri, destination, 0)
        return destination.absolutePath
    }

    private fun copyDocument(
        treeUri: Uri,
        documentUri: Uri,
        destination: File,
        depth: Int,
    ) {
        if (depth > 48) throw IllegalStateException("The folder is nested too deeply.")
        val mime = queryMime(documentUri)
        if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
            destination.mkdirs()
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getDocumentId(documentUri),
            )
            contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                while (cursor.moveToNext()) {
                    val id = cursor.getString(idIndex)
                    val name = safeName(cursor.getString(nameIndex) ?: "file")
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id)
                    copyDocument(
                        treeUri,
                        childUri,
                        uniqueChild(destination, name),
                        depth + 1,
                    )
                }
            }
            return
        }

        destination.parentFile?.mkdirs()
        contentResolver.openInputStream(documentUri)?.use { input ->
            destination.outputStream().use { output -> input.copyTo(output) }
        } ?: throw IllegalStateException("A file in that folder could not be opened.")
    }

    private fun queryMime(uri: Uri): String {
        contentResolver.query(
            uri,
            arrayOf(DocumentsContract.Document.COLUMN_MIME_TYPE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0) ?: ""
        }
        return ""
    }

    private fun queryName(uri: Uri): String {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0) ?: ""
        }
        return ""
    }

    private fun safeName(raw: String): String {
        val cleaned = raw
            .replace("/", "-")
            .replace("\\", "-")
            .replace("\u0000", "")
            .trim()
        return when {
            cleaned.isEmpty() -> "file"
            cleaned == "." || cleaned == ".." -> "file"
            else -> cleaned
        }
    }

    private fun uniqueChild(parent: File, name: String): File {
        var candidate = File(parent, name)
        if (!candidate.exists()) return candidate
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val suffix = if (dot > 0) name.substring(dot) else ""
        var index = 2
        while (candidate.exists()) {
            candidate = File(parent, "$stem ($index)$suffix")
            index++
        }
        return candidate
    }
}
