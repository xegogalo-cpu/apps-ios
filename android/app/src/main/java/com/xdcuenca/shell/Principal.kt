package com.xdcuenca.shell

import android.Manifest
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.webkit.*
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import java.io.File

/** maXD / Bodega XD a pantalla completa: el mismo sistema web, con avisos, cámara, ubicación y archivos nativos. */
class Principal : AppCompatActivity() {

    companion object { const val EXTRA_URL = "url" }

    private lateinit var web: WebView
    private lateinit var puente: Puente
    private lateinit var sinConexion: View
    private val base: Uri by lazy { Uri.parse(BuildConfig.SISTEMA) }
    private val propios: List<String> by lazy { BuildConfig.HOSTS_PROPIOS.split(",").map { it.trim() } }

    // ── Permisos ────────────────────────────────────────────────
    private var trasPermisoAvisos: (() -> Unit)? = null
    private val pedirAvisos = registerForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        getSharedPreferences("xd_push", MODE_PRIVATE).edit().putBoolean("negado", !ok).apply()
        trasPermisoAvisos?.invoke(); trasPermisoAvisos = null
    }
    fun pedirPermisoAvisos(luego: () -> Unit) {
        if (Build.VERSION.SDK_INT < 33) { luego(); return }
        trasPermisoAvisos = luego
        pedirAvisos.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
    fun permisoAvisosNegado(): Boolean =
        getSharedPreferences("xd_push", MODE_PRIVATE).getBoolean("negado", false) &&
            !shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)

    private var pedidoMedios: PermissionRequest? = null
    private val pedirMedios = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { r ->
        val p = pedidoMedios ?: return@registerForActivityResult
        val ok = p.resources.filter { rec ->
            when (rec) {
                PermissionRequest.RESOURCE_VIDEO_CAPTURE -> r[Manifest.permission.CAMERA] == true || tiene(Manifest.permission.CAMERA)
                PermissionRequest.RESOURCE_AUDIO_CAPTURE -> r[Manifest.permission.RECORD_AUDIO] == true || tiene(Manifest.permission.RECORD_AUDIO)
                else -> false
            }
        }
        if (ok.isNotEmpty()) p.grant(ok.toTypedArray()) else p.deny()
        pedidoMedios = null
    }

    private var geoOrigen: String? = null
    private var geoCallback: GeolocationPermissions.Callback? = null
    private val pedirUbicacion = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { r ->
        val ok = r[Manifest.permission.ACCESS_FINE_LOCATION] == true || r[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        geoCallback?.invoke(geoOrigen, ok, false); geoCallback = null
    }

    // ── Archivos y cámara (foto de marcación, comprobantes) ──────
    private var archivosCallback: ValueCallback<Array<Uri>>? = null
    private var fotoUri: Uri? = null
    private val elegirArchivo = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { res ->
        val cb = archivosCallback ?: return@registerForActivityResult
        var uris: Array<Uri>? = null
        if (res.resultCode == RESULT_OK) {
            val d = res.data
            uris = when {
                d?.clipData != null -> Array(d.clipData!!.itemCount) { d.clipData!!.getItemAt(it).uri }
                d?.data != null -> arrayOf(d.data!!)
                fotoUri != null -> arrayOf(fotoUri!!)
                else -> null
            }
        }
        cb.onReceiveValue(uris); archivosCallback = null; fotoUri = null
    }
    private val permisoCamaraArchivo = registerForActivityResult(ActivityResultContracts.RequestPermission()) { abrirSelector(ultimoParams) }
    private var ultimoParams: WebChromeClient.FileChooserParams? = null

    private fun tiene(p: String) = ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.parseColor(getString(R.string.color_barra))

        val raiz = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        web = WebView(this)
        sinConexion = vistaSinConexion()
        raiz.addView(web, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        raiz.addView(sinConexion, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        sinConexion.visibility = View.GONE
        setContentView(raiz)

        /* 7-nov-2026 · Android 15+ con targetSdk 35/36 dibuja la app DEBAJO de la barra de estado y de la barra de
           navegación (edge-to-edge obligatorio). En maXD el botón "Atender yo" del chat de WhatsApp quedaba tapado por
           la barra de gestos y el encabezado por la hora. Se reserva ese espacio con relleno, y también el del teclado
           (ime) para que no tape lo que se escribe. */
        raiz.setBackgroundColor(Color.parseColor(getString(R.string.color_barra)))
        ViewCompat.setOnApplyWindowInsetsListener(raiz) { v, insets ->
            val b = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout() or WindowInsetsCompat.Type.ime()
            )
            v.setPadding(b.left, b.top, b.right, b.bottom)
            WindowInsetsCompat.CONSUMED
        }

        with(web.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            mediaPlaybackRequiresUserGesture = false
            setGeolocationEnabled(true)
            allowFileAccess = false
            javaScriptCanOpenWindowsAutomatically = true
            setSupportMultipleWindows(true)
            userAgentString = "$userAgentString ${BuildConfig.MARCA_UA}"
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)

        puente = Puente(this)
        puente.web = web
        web.addJavascriptInterface(puente, "XDAndroid")
        val inicioOk = WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
        if (inicioOk) {
            WebViewCompat.addDocumentStartJavaScript(web, Puente.SCRIPT_INICIO, propios.map { "https://$it" }.toSet())
        }

        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, req: WebResourceRequest): Boolean = abrirAfuera(req.url)
            override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                if (!inicioOk) view.evaluateJavascript(Puente.SCRIPT_INICIO, null)
            }
            override fun onPageFinished(view: WebView, url: String?) {
                if (!inicioOk) view.evaluateJavascript(Puente.SCRIPT_INICIO, null)
                puente.avisarPagina()
                // Si ya dio permiso antes, se refresca el token en silencio.
                if (puente.permisoConcedido()) puente.pedirToken()
            }
            override fun onReceivedError(view: WebView, req: WebResourceRequest, err: WebResourceError) {
                if (req.isForMainFrame) { sinConexion.visibility = View.VISIBLE; web.visibility = View.GONE }
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                runOnUiThread {
                    val host = Uri.parse(request.origin.toString()).host ?: ""
                    if (propios.none { host.endsWith(it) }) { request.deny(); return@runOnUiThread }
                    val faltan = mutableListOf<String>()
                    if (request.resources.contains(PermissionRequest.RESOURCE_VIDEO_CAPTURE) && !tiene(Manifest.permission.CAMERA)) faltan += Manifest.permission.CAMERA
                    if (request.resources.contains(PermissionRequest.RESOURCE_AUDIO_CAPTURE) && !tiene(Manifest.permission.RECORD_AUDIO)) faltan += Manifest.permission.RECORD_AUDIO
                    if (faltan.isEmpty()) request.grant(request.resources) else { pedidoMedios = request; pedirMedios.launch(faltan.toTypedArray()) }
                }
            }
            override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) {
                val host = Uri.parse(origin).host ?: ""
                if (propios.none { host.endsWith(it) }) { callback.invoke(origin, false, false); return }
                if (tiene(Manifest.permission.ACCESS_FINE_LOCATION) || tiene(Manifest.permission.ACCESS_COARSE_LOCATION)) { callback.invoke(origin, true, false); return }
                geoOrigen = origin; geoCallback = callback
                pedirUbicacion.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
            }
            override fun onShowFileChooser(view: WebView, cb: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                archivosCallback?.onReceiveValue(null)
                archivosCallback = cb; ultimoParams = params
                if (quiereCamara(params) && !tiene(Manifest.permission.CAMERA)) permisoCamaraArchivo.launch(Manifest.permission.CAMERA)
                else abrirSelector(params)
                return true
            }
            /** window.open (reportes, impresión, WhatsApp Web): se abre en el navegador para no perder la caja. */
            override fun onCreateWindow(view: WebView, isDialog: Boolean, isUserGesture: Boolean, resultMsg: android.os.Message): Boolean {
                val tmp = WebView(this@Principal)
                tmp.webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(v: WebView, r: WebResourceRequest): Boolean {
                        abrirEnNavegador(r.url); v.destroy(); return true
                    }
                }
                (resultMsg.obj as WebView.WebViewTransport).webView = tmp
                resultMsg.sendToTarget()
                return true
            }
        }
        web.setDownloadListener { url, _, _, _, _ -> abrirEnNavegador(Uri.parse(url)) }

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (web.canGoBack()) web.goBack() else { isEnabled = false; onBackPressedDispatcher.onBackPressed() }
            }
        })

        val destino = destino(intent?.getStringExtra(EXTRA_URL))
        if (savedInstanceState != null) web.restoreState(savedInstanceState) else web.loadUrl((destino ?: base).toString())
    }

    override fun onSaveInstanceState(outState: Bundle) { super.onSaveInstanceState(outState); web.saveState(outState) }

    /** Al tocar un aviso con la app abierta: se va a la parte del sistema que trae el aviso. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        destino(intent.getStringExtra(EXTRA_URL))?.let { web.loadUrl(it.toString()) }
    }

    override fun onResume() { super.onResume(); if (::puente.isInitialized) puente.avisarPagina() }

    /** "./" solo abre la app; "#walkie" va a esa parte; "/?app=tienda#seguir-…" al seguimiento. Igual que en iPhone. */
    private fun destino(s: String?): Uri? {
        if (s.isNullOrBlank() || s == "./" || s == "/") return null
        val u: Uri = if (s.startsWith("#") || s.startsWith("./#")) base.buildUpon().fragment(s.substringAfter("#")).build()
                     else base.buildUpon().build().let { b -> Uri.parse(java.net.URI(b.toString()).resolve(s).toString()) }
        val host = u.host ?: return null
        if (propios.none { host.endsWith(it) }) return null
        // Un parámetro nuevo obliga a abrir la página de nuevo: así la tienda vuelve a leer a qué pedido ir.
        return u.buildUpon().appendQueryParameter("av", (System.currentTimeMillis() / 1000).toString()).build()
    }

    /** WhatsApp, llamadas, correo, mapas y tiendas se abren en su app; lo de otros sitios, en el navegador. */
    private fun abrirAfuera(u: Uri): Boolean {
        val esquema = (u.scheme ?: "").lowercase()
        val host = (u.host ?: "").lowercase()
        if (esquema == "http" || esquema == "https") {
            if (propios.any { host.endsWith(it) }) return false
            if (host.endsWith("firebaseapp.com") || host.endsWith("googleapis.com") || host.endsWith("google.com") && u.path?.startsWith("/recaptcha") == true) return false
            abrirEnNavegador(u); return true
        }
        if (esquema == "intent") {
            try { startActivity(Intent.parseUri(u.toString(), Intent.URI_INTENT_SCHEME)) } catch (_: Exception) {}
            return true
        }
        abrirEnNavegador(u); return true
    }

    private fun abrirEnNavegador(u: Uri) {
        try { startActivity(Intent(Intent.ACTION_VIEW, u).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: ActivityNotFoundException) {}
    }

    private fun quiereCamara(p: WebChromeClient.FileChooserParams?): Boolean =
        p != null && (p.isCaptureEnabled || p.acceptTypes.any { it.startsWith("image") })

    private fun abrirSelector(p: WebChromeClient.FileChooserParams?) {
        val elegir = try { p?.createIntent() } catch (_: Exception) { null } ?: Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE); type = "*/*"
        }
        if (p?.mode == WebChromeClient.FileChooserParams.MODE_OPEN_MULTIPLE) elegir.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        val extras = mutableListOf<Intent>()
        if (quiereCamara(p) && tiene(Manifest.permission.CAMERA)) {
            try {
                val f = File.createTempFile("foto_", ".jpg", File(cacheDir, "fotos").apply { mkdirs() })
                fotoUri = FileProvider.getUriForFile(this, "$packageName.archivos", f)
                extras += Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE).putExtra(android.provider.MediaStore.EXTRA_OUTPUT, fotoUri)
                    .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            } catch (_: Exception) { fotoUri = null }
        }
        val i = if (p?.isCaptureEnabled == true && extras.isNotEmpty()) extras.first()
                else Intent.createChooser(elegir, null).apply { if (extras.isNotEmpty()) putExtra(Intent.EXTRA_INITIAL_INTENTS, extras.toTypedArray()) }
        try { elegirArchivo.launch(i) } catch (_: Exception) { archivosCallback?.onReceiveValue(null); archivosCallback = null }
    }

    private fun vistaSinConexion(): View {
        val v = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = android.view.Gravity.CENTER
            setPadding(64, 64, 64, 64)
            setBackgroundColor(Color.WHITE)
        }
        v.addView(TextView(this).apply { text = getString(R.string.sin_conexion); textSize = 18f; gravity = android.view.Gravity.CENTER; setTextColor(Color.parseColor("#1D1D1F")) })
        v.addView(Button(this).apply {
            text = getString(R.string.reintentar)
            setOnClickListener { v.visibility = View.GONE; web.visibility = View.VISIBLE; if (web.url == null) web.loadUrl(base.toString()) else web.reload() }
        })
        return v
    }
}
