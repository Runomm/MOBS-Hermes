package com.mobstudios.hermes

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 6r-d: app-embedded dual mic plugin (pub paketi değil, manuel register)
        flutterEngine.plugins.add(HermesDualMicPlugin())
    }
}
