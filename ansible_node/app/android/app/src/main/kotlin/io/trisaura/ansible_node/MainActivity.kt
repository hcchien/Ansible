package io.trisaura.ansible_node

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ansible_node/backup_policy"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareRemoteMirrorDirectory" -> {
                    val name = call.argument<String>("name")
                    if (name.isNullOrBlank()) {
                        result.error(
                            "invalid_arguments",
                            "Missing no-backup directory name",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    val directory = File(noBackupFilesDir, name)
                    if (!directory.exists() && !directory.mkdirs()) {
                        result.error(
                            "backup_policy_failed",
                            "Could not create ${directory.absolutePath}",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    result.success(directory.absolutePath)
                }
                else -> result.notImplemented()
            }
        }
    }
}
