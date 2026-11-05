package com.xdcuenca.shell

import android.Manifest
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Recibe los avisos de Firebase Cloud Messaging y los pinta siempre la app (esté abierta, en segundo plano o cerrada):
 * el servidor (netlify/functions/fcm.js) los manda solo como `data` con titulo, mensaje, tag, url y urgente.
 */
class Avisos : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        Puente.guardarToken(this, token)
        Puente.actual?.avisarPagina()
    }

    override fun onMessageReceived(m: RemoteMessage) {
        val d = m.data
        val titulo = d["titulo"] ?: m.notification?.title ?: getString(R.string.app_name)
        val mensaje = d["mensaje"] ?: m.notification?.body ?: ""
        val tag = d["tag"] ?: "xd"
        val url = d["url"] ?: ""
        val urgente = d["urgente"] == "1"
        mostrar(titulo, mensaje, tag, url, urgente)
    }

    private fun mostrar(titulo: String, mensaje: String, tag: String, url: String, urgente: Boolean) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val abrir = Intent(this, Principal::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(Principal.EXTRA_URL, url)
        }
        val pi = PendingIntent.getActivity(this, tag.hashCode(), abrir,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(this, if (urgente) Aplicacion.CANAL_URGENTE else Aplicacion.CANAL)
            .setSmallIcon(R.drawable.ic_aviso)
            .setContentTitle(titulo)
            .setContentText(mensaje)
            .setStyle(NotificationCompat.BigTextStyle().bigText(mensaje))
            .setAutoCancel(true)
            .setOngoing(false)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(if (urgente) NotificationCompat.CATEGORY_ALARM else NotificationCompat.CATEGORY_MESSAGE)
            .setContentIntent(pi)
            .build()
        try { NotificationManagerCompat.from(this).notify(tag, 1, n) } catch (_: SecurityException) {}
    }
}
