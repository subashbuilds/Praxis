package com.subash.praxis

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private companion object {
        const val PICK_IMPORT_FOLDER = 4711
    }

    private var pendingFolderResult: MethodChannel.Result? = null
    private var notificationPermissionAsked = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureBackgroundJobs(flutterEngine)
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
                "sealSecret", "openSecret" -> {
                    // Keystore work is quick but must not run on the platform
                    // thread. The reply carries only the transformed value.
                    val value = call.argument<String>("value") ?: ""
                    val sealing = call.method == "sealSecret"
                    Thread {
                        try {
                            val output = if (sealing) sealSecret(value) else openSecret(value)
                            runOnUiThread { result.success(output) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "keystore",
                                    error.message ?: "The keystore operation failed.",
                                    null,
                                )
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Starts or updates the foreground service that keeps a long build, upload
    /// or agent run alive while Praxis is in the background. The service is
    /// deliberately not sticky: Dart cannot resume work after Android kills the
    /// process, so the journal marks that job interrupted instead of showing a
    /// notification for work that is no longer running.
    private fun configureBackgroundJobs(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "praxis/background_jobs",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start", "update" -> {
                    askForNotificationPermission()
                    val title = call.argument<String>("title") ?: "Praxis is working"
                    val detail = call.argument<String>("detail") ?: ""
                    val intent = Intent(this, BackgroundJobService::class.java).apply {
                        action = BackgroundJobService.ACTION_START
                        putExtra(BackgroundJobService.EXTRA_TITLE, title)
                        putExtra(BackgroundJobService.EXTRA_DETAIL, detail)
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    } catch (error: Exception) {
                        // A denied background start must not crash the running
                        // action; the journal still records its result.
                        result.error(
                            "background_service",
                            error.message ?: "Could not start the foreground service.",
                            null,
                        )
                    }
                }
                "stop" -> {
                    stopService(Intent(this, BackgroundJobService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// AES/GCM with a key generated inside the Android Keystore. The key is
    /// never exported, so a copy of the preferences file is useless on another
    /// device. The IV is prepended to the ciphertext.
    private fun keystoreSecret(): SecretKey {
        val alias = "praxis.secrets.v1"
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getEntry(alias, null) as? KeyStore.SecretKeyEntry)?.let {
            return it.secretKey
        }
        val generator =
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun sealSecret(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, keystoreSecret())
        val iv = cipher.iv
        val body = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val combined = ByteArray(iv.size + body.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(body, 0, combined, iv.size, body.size)
        return Base64.encodeToString(combined, Base64.NO_WRAP)
    }

    private fun openSecret(sealed: String): String {
        val combined = Base64.decode(sealed, Base64.NO_WRAP)
        if (combined.size <= 12) throw IllegalArgumentException("Not a sealed value.")
        val iv = combined.copyOfRange(0, 12)
        val body = combined.copyOfRange(12, combined.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            keystoreSecret(),
            GCMParameterSpec(128, iv),
        )
        return String(cipher.doFinal(body), Charsets.UTF_8)
    }

    private fun askForNotificationPermission() {
        if (notificationPermissionAsked) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        notificationPermissionAsked = true
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4712)
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
