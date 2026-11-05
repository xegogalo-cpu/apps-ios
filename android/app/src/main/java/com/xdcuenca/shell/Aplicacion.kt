package com.xdcuenca.shell

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions

/** Arranca Firebase (sin google-services.json: los datos van en BuildConfig) y crea los canales de avisos. */
class Aplicacion : Application() {
    override fun onCreate() {
        super.onCreate()
        iniciarFirebase(this)
        crearCanales()
    }

    private fun crearCanales() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        val sonido = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val attrs = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build()
        val normal = NotificationChannel(CANAL, getString(R.string.canal_avisos), NotificationManager.IMPORTANCE_HIGH).apply {
            enableVibration(true); setSound(sonido, attrs)
        }
        val urgente = NotificationChannel(CANAL_URGENTE, getString(R.string.canal_urgentes), NotificationManager.IMPORTANCE_HIGH).apply {
            enableVibration(true); vibrationPattern = longArrayOf(0, 150, 80, 150, 80, 150); setSound(sonido, attrs)
        }
        nm.createNotificationChannel(normal)
        nm.createNotificationChannel(urgente)
    }

    companion object {
        const val CANAL = "avisos"
        const val CANAL_URGENTE = "urgentes"

        fun iniciarFirebase(app: Application) {
            if (FirebaseApp.getApps(app).isNotEmpty()) return
            if (BuildConfig.FIREBASE_API_KEY.isEmpty()) return
            val op = FirebaseOptions.Builder()
                .setApiKey(BuildConfig.FIREBASE_API_KEY)
                .setApplicationId(BuildConfig.FIREBASE_APP_ID)
                .setProjectId(BuildConfig.FIREBASE_PROJECT)
                .setGcmSenderId(BuildConfig.FIREBASE_SENDER)
                .build()
            FirebaseApp.initializeApp(app, op)
        }
    }
}
