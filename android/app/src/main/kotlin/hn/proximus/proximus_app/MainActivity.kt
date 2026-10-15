package hn.proximus.proximus_app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Opens the dialer, WhatsApp or the maps app; the user always confirms in that app.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "proximus/external").setMethodCallHandler { call, result ->
            val uri = call.argument<String>("uri")
            if (call.method != "open" || uri == null) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val action = if (uri.startsWith("tel:")) Intent.ACTION_DIAL else Intent.ACTION_VIEW
            try {
                startActivity(Intent(action, Uri.parse(uri)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(true)
            } catch (error: ActivityNotFoundException) {
                result.success(false)
            }
        }
    }
}
