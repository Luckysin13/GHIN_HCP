package com.example.ghin_golf

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Lets the Dart side ask the user where to save an exported backup.
 *
 * file_selector implements getSaveLocation on web and desktop but not on
 * Android, so the Save As dialog is driven here through the Storage Access
 * Framework instead. ACTION_CREATE_DOCUMENT hands back a content:// uri
 * rather than a file path, so the file is written through ContentResolver and
 * needs no real path on disk.
 *
 * Uses startActivityForResult rather than registerForActivityResult because
 * FlutterActivity extends android.app.Activity, which does not provide the
 * newer ActivityResultLauncher API.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "ghin_golf/backup"
        const val REQUEST_CREATE_DOCUMENT = 4711
    }

    /**
     * The pick still waiting on the dialog. Held across the activity result
     * because the channel call cannot complete until the user answers, and
     * null when no dialog is open.
     */
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickDestination" -> pickDestination(call, result)
                    "writeTo" -> writeTo(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickDestination(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("suggestedName") ?: "ghin-golf-backup.json"
        val mime = call.argument<String>("mimeType") ?: "application/json"
        if (pending != null) {
            // A second pick while one is open would leave the first result
            // hanging forever.
            result.error("busy", "A save dialog is already open.", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
            putExtra(Intent.EXTRA_TITLE, name)
        }
        pending = result
        try {
            startActivityForResult(intent, REQUEST_CREATE_DOCUMENT)
        } catch (e: Exception) {
            pending = null
            result.error("unavailable", e.message ?: "No save dialog.", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CREATE_DOCUMENT) return
        val result = pending
        pending = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        // A null uri is the user backing out, which Dart reads as cancelled
        // rather than as a failure.
        result?.success(uri?.toString())
    }

    private fun writeTo(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val contents = call.argument<String>("contents")
        if (uri == null || contents == null) {
            result.error("bad_args", "uri and contents are both required.", null)
            return
        }
        val ok = try {
            contentResolver.openOutputStream(Uri.parse(uri))?.use { stream ->
                stream.write(contents.toByteArray(Charsets.UTF_8))
                stream.flush()
                true
            } ?: false
        } catch (e: Exception) {
            // Reported as false so Dart can tell the user nothing was
            // written, instead of claiming a success that left a bad file.
            false
        }
        result.success(ok)
    }
}
