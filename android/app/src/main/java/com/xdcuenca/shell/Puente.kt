package com.xdcuenca.shell

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import org.json.JSONObject

/**
 * Puente de avisos entre Android (FCM) y la página de maXD / la tienda Bodega XD. Es EL MISMO contrato que la app de iPhone:
 * la página llama `window.webkit.messageHandlers.xdPush.postMessage({accion:'pedir'|'estado'})` (este objeto lo pone la app)
 * y recibe `window.__xdPushNativo({permiso, token, bundle, env, plataforma:'android'})`.
 */
class Puente(private val actividad: Principal) {
    var web: WebView? = null

    init { actual = this }

    /** Script que se pone al inicio de cada página: crea el mismo objeto que en iPhone. */
    companion object {
        var actual: Puente? = null
        private const val PREFS = "xd_push"

        const val SCRIPT_INICIO = """
            (function(){ try{
              if(!window.XDAndroid) return;
              window.webkit = window.webkit || {};
              window.webkit.messageHandlers = window.webkit.messageHandlers || {};
              window.webkit.messageHandlers.xdPush = { postMessage: function(m){ try{ window.XDAndroid.post(JSON.stringify(m||{})); }catch(e){} } };
              window.__APP_ANDROID__ = true;
            }catch(e){} })();
        """

        fun guardarToken(ctx: Context, token: String) {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("token", token).apply()
        }
        fun tokenGuardado(ctx: Context): String? = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("token", null)
    }

    @JavascriptInterface
    fun post(json: String?) {
        val accion = try { JSONObject(json ?: "{}").optString("accion", "estado") } catch (_: Exception) { "estado" }
        actividad.runOnUiThread {
            if (accion == "pedir" && !permisoConcedido()) actividad.pedirPermisoAvisos { pedirToken() }
            else pedirToken()
        }
    }

    fun permisoConcedido(): Boolean {
        if (!NotificationManagerCompat.from(actividad).areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= 33) {
            return ContextCompat.checkSelfPermission(actividad, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    private fun permiso(): String {
        if (permisoConcedido()) return "granted"
        if (Build.VERSION.SDK_INT >= 33 && actividad.permisoAvisosNegado()) return "denied"
        if (Build.VERSION.SDK_INT < 33) return "denied"   // antes de Android 13 solo se apagan desde Ajustes
        return "default"
    }

    /** Con permiso, pide (o refresca) el token de Firebase y se lo cuenta a la página. */
    fun pedirToken() {
        if (!permisoConcedido() || FirebaseApp.getApps(actividad).isEmpty()) { avisarPagina(); return }
        try {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { t ->
                if (t.isSuccessful && !t.result.isNullOrEmpty()) guardarToken(actividad, t.result)
                avisarPagina()
            }
        } catch (_: Exception) { avisarPagina() }
    }

    /** Android → página: permiso y token actuales. */
    fun avisarPagina() {
        val tok = if (permisoConcedido()) tokenGuardado(actividad) else null
        val o = JSONObject()
            .put("permiso", permiso())
            .put("token", tok ?: JSONObject.NULL)
            .put("bundle", actividad.packageName)
            .put("env", "production")
            .put("plataforma", "android")
        val js = "window.__xdPushNativo && window.__xdPushNativo($o);"
        actividad.runOnUiThread { web?.evaluateJavascript(js, null) }
    }
}
