package com.example.arsip_berita_app

import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.arsip_berita_app/samsung_notes"
    private val openDocumentTreeRequestCode = 1001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickDirectory" -> pickDirectory(result)
                    "listFiles" -> listFiles(call, result)
                    "readBytes" -> readBytes(call, result)
                    "hasPersistedPermission" -> hasPersistedPermission(call, result)
                    "releasePersistedPermission" -> releasePersistedPermission(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickDirectory(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("IN_PROGRESS", "Directory picker already in progress", null)
            return
        }
        pendingResult = result
        try {
            // Buka picker langsung di folder Download agar dekat dengan lokasi
            // export Samsung Notes (Save as file). Jika URI tidak valid,
            // sistem akan menampilkan lokasi default.
            val initialUri = Uri.parse(
                "content://com.android.externalstorage.documents/document/primary%3ADownload"
            )
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                putExtra("android.provider.extra.INITIAL_URI", initialUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            }
            startActivityForResult(intent, openDocumentTreeRequestCode)
        } catch (e: Exception) {
            pendingResult = null
            result.error("PICK_FAILED", e.message, null)
        }
    }

    @Deprecated("Use Activity Result APIs when available")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != openDocumentTreeRequestCode) return

        val result = pendingResult
        pendingResult = null
        val uri = if (resultCode == RESULT_OK) data?.data else null
        if (uri != null) {
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) {
            }
        }
        result?.success(uri?.toString())
    }

    private fun listFiles(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("BAD_ARGS", "uri required", null)
            return
        }
        val dir = DocumentFile.fromTreeUri(this, Uri.parse(uriString))
        if (dir == null) {
            result.error("NOT_FOUND", "Directory not found", null)
            return
        }
        val files = mutableListOf<Map<String, Any?>>()
        for (item in dir.listFiles()) {
            if (item.isFile) {
                files.add(
                    mapOf(
                        "uri" to item.uri.toString(),
                        "name" to (item.name ?: ""),
                        "size" to item.length(),
                        "lastModified" to item.lastModified()
                    )
                )
            }
        }
        result.success(files)
    }

    private fun readBytes(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("BAD_ARGS", "uri required", null)
            return
        }
        try {
            contentResolver.openInputStream(Uri.parse(uriString))?.use { input ->
                result.success(input.readBytes())
                return
            }
            result.error("READ_FAILED", "Cannot open file", null)
        } catch (e: Exception) {
            result.error("READ_FAILED", e.message, null)
        }
    }

    private fun hasPersistedPermission(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("BAD_ARGS", "uri required", null)
            return
        }
        val uri = Uri.parse(uriString)
        result.success(contentResolver.persistedUriPermissions.any { it.uri == uri })
    }

    private fun releasePersistedPermission(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("BAD_ARGS", "uri required", null)
            return
        }
        try {
            contentResolver.releasePersistableUriPermission(
                Uri.parse(uriString),
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }
}
