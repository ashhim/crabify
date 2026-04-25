package com.example.crabify

import android.annotation.SuppressLint
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val mediaChannel = "crabify/device_media"
    private val supportedExtensions = setOf(".mp3", ".wav", ".m4a", ".aac", ".ogg", ".mp4")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanSongs" -> result.success(scanSongs())
                    else -> result.notImplemented()
                }
            }
    }

    @SuppressLint("Range")
    private fun scanSongs(): List<Map<String, Any?>> {
        val results = linkedMapOf<String, Map<String, Any?>>()

        val audioProjection = arrayOf(
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION
        )
        val audioSelection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"

        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            audioProjection,
            audioSelection,
            null,
            "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val path = cursor.getString(cursor.getColumnIndex(MediaStore.Audio.Media.DATA)) ?: continue
                val extension = path.substringAfterLast('.', "").lowercase()
                if (!supportedExtensions.contains(".$extension")) {
                    continue
                }
                results[path] = mapOf(
                    "path" to path,
                    "title" to cursor.getString(cursor.getColumnIndex(MediaStore.Audio.Media.TITLE)),
                    "artistName" to cursor.getString(cursor.getColumnIndex(MediaStore.Audio.Media.ARTIST)),
                    "albumTitle" to cursor.getString(cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM)),
                    "durationSeconds" to (cursor.getLong(cursor.getColumnIndex(MediaStore.Audio.Media.DURATION)) / 1000L).toInt(),
                    "isVideoSource" to false
                )
            }
        }

        val videoProjection = arrayOf(
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.TITLE,
            MediaStore.Video.Media.ARTIST,
            MediaStore.Video.Media.DURATION
        )

        contentResolver.query(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            videoProjection,
            null,
            null,
            "${MediaStore.Video.Media.DATE_MODIFIED} DESC"
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val path = cursor.getString(cursor.getColumnIndex(MediaStore.Video.Media.DATA)) ?: continue
                if (!path.lowercase().endsWith(".mp4")) {
                    continue
                }
                results.putIfAbsent(
                    path,
                    mapOf(
                        "path" to path,
                        "title" to cursor.getString(cursor.getColumnIndex(MediaStore.Video.Media.TITLE)),
                        "artistName" to (cursor.getString(cursor.getColumnIndex(MediaStore.Video.Media.ARTIST)) ?: "Unknown artist"),
                        "albumTitle" to null,
                        "durationSeconds" to (cursor.getLong(cursor.getColumnIndex(MediaStore.Video.Media.DURATION)) / 1000L).toInt(),
                        "isVideoSource" to true
                    )
                )
            }
        }

        return results.values.toList()
    }
}
