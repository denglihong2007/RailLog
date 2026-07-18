package com.deliho.raillog

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.deliho.raillog/downloads"
    private val storagePermissionRequest = 7102
    private var pendingSave: PendingSave? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                handleSave(call, result)
            }
    }

    private fun handleSave(call: MethodCall, result: MethodChannel.Result) {
        val requestedName = call.argument<String>("name") ?: "RailLog_file"
        val bytes = call.argument<ByteArray>("bytes")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (bytes == null) {
            result.error("invalid_bytes", "文件内容为空", null)
            return
        }
        val save = PendingSave(sanitizeFileName(requestedName), bytes, mimeType, result)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingSave = save
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                storagePermissionRequest,
            )
            return
        }
        saveInBackground(save)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != storagePermissionRequest) return
        val save = pendingSave ?: return
        pendingSave = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            saveInBackground(save)
        } else {
            save.result.error("storage_permission_denied", "需要存储权限才能保存到 Downloads", null)
        }
    }

    private fun saveInBackground(save: PendingSave) {
        Thread {
            try {
                val location = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    saveWithMediaStore(save)
                } else {
                    saveToLegacyDownloads(save)
                }
                runOnUiThread { save.result.success(location) }
            } catch (error: Exception) {
                runOnUiThread {
                    save.result.error("save_failed", error.message ?: "保存文件失败", null)
                }
            }
        }.start()
    }

    private fun saveWithMediaStore(save: PendingSave): String {
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, save.name)
            put(MediaStore.Downloads.MIME_TYPE, save.mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("无法创建 Downloads 文件")
        try {
            resolver.openOutputStream(uri, "w")?.use { it.write(save.bytes) }
                ?: throw IllegalStateException("无法写入 Downloads 文件")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
        return "Downloads/${save.name}"
    }

    @Suppress("DEPRECATION")
    private fun saveToLegacyDownloads(save: PendingSave): String {
        val directory = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("无法打开 Downloads 目录")
        }
        val target = uniqueFile(directory, save.name)
        target.writeBytes(save.bytes)
        return target.absolutePath
    }

    private fun uniqueFile(directory: File, name: String): File {
        val requested = File(directory, name)
        if (!requested.exists()) return requested
        val extensionIndex = name.lastIndexOf('.')
        val stem = if (extensionIndex > 0) name.substring(0, extensionIndex) else name
        val extension = if (extensionIndex > 0) name.substring(extensionIndex) else ""
        var index = 1
        while (true) {
            val candidate = File(directory, "$stem ($index)$extension")
            if (!candidate.exists()) return candidate
            index++
        }
    }

    private fun sanitizeFileName(value: String): String {
        val sanitized = File(value).name
            .replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_")
            .trim()
        return sanitized.ifBlank { "RailLog_file" }
    }

    private data class PendingSave(
        val name: String,
        val bytes: ByteArray,
        val mimeType: String,
        val result: MethodChannel.Result,
    )
}
