package hn.proximus.proximus_app

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Opens the dialer, WhatsApp or the maps app; the user always confirms in that app.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "proximus/external").setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                    val action = if (uri.startsWith("tel:")) Intent.ACTION_DIAL else Intent.ACTION_VIEW
                    result.success(start(Intent(action, Uri.parse(uri))))
                }
                // With power saving on, Android cuts the network of apps in the background
                // unless they are exempt from battery restrictions; then nothing syncs with the app closed.
                "isBackgroundAllowed" -> {
                    val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(power.isIgnoringBatteryOptimizations(packageName))
                }
                "requestBackground" -> result.success(requestBackground())
                else -> result.notImplemented()
            }
        }
    }

    @SuppressLint("BatteryLife")
    private fun requestBackground(): Boolean {
        // The system asks the user; if this phone does not offer that dialog, open the battery settings.
        val ask = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
        return start(ask) || start(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
    }

    private fun start(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (error: ActivityNotFoundException) {
        false
    }
}
