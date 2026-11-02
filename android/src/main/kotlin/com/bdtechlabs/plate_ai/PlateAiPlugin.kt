package com.bdtechlabs.plate_ai

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

class PlateAiPlugin : FlutterPlugin {
    private var channel: MethodChannel? = null
    private var engine: PlateEngine? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        engine = PlateEngine(binding.applicationContext, binding.flutterAssets)
        channel = MethodChannel(binding.binaryMessenger, "plate_ai/engine").apply {
            setMethodCallHandler(engine)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        engine?.shutdown()
        engine = null
    }
}
