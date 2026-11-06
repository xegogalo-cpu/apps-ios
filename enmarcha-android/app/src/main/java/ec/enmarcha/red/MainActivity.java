package ec.enmarcha.red;

import android.Manifest;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Message;
import android.webkit.CookieManager;
import android.webkit.GeolocationPermissions;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import com.google.firebase.messaging.FirebaseMessaging;

/**
 * En Marcha para Android: abre la web de la campaña dentro de la app y recibe los avisos push
 * con Firebase Cloud Messaging, para que lleguen como notificaciones de "En Marcha".
 * La web se comunica con la app por window.EnMarchaAndroid.postMessage("avisos" | "listo")
 * y recibe el token en window.recibirTokenNativo(token), igual que en la app de iPhone.
 */
public class MainActivity extends Activity {

    static final String APP = "https://en-marcha-red.web.app/";
    static final String HOST = "en-marcha-red.web.app";
    static final String PREFS = "enmarcha";

    private static final int REQ_ARCHIVO = 10;
    private static final int REQ_AVISOS = 11;
    private static final int REQ_CAMARA = 12;
    private static final int REQ_UBICACION = 13;

    private WebView web;
    private ValueCallback<Uri[]> archivos;
    private PermissionRequest pedidoCamara;
    private GeolocationPermissions.Callback ubicacionCallback;
    private String ubicacionOrigen;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        AvisosService.crearCanal(this);
        getWindow().setStatusBarColor(Color.rgb(27, 35, 72));

        web = new WebView(this);
        web.setBackgroundColor(Color.rgb(242, 243, 248));
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setGeolocationEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setSupportMultipleWindows(true);
        s.setJavaScriptCanOpenWindowsAutomatically(true);
        s.setUserAgentString(s.getUserAgentString() + " EnMarcha-Android/1.1");
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, true);

        web.addJavascriptInterface(new Puente(), "EnMarchaAndroid");

        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri u = request.getUrl();
                if (esPropio(u)) return false;
                abrirFuera(u);
                return true;
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                enviarToken();
            }
        });

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (archivos != null) archivos.onReceiveValue(null);
                archivos = callback;
                try {
                    startActivityForResult(params.createIntent(), REQ_ARCHIVO);
                } catch (ActivityNotFoundException e) {
                    archivos = null;
                    return false;
                }
                return true;
            }

            @Override
            public void onPermissionRequest(PermissionRequest request) {
                runOnUiThread(() -> {
                    if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                        request.grant(request.getResources());
                    } else {
                        pedidoCamara = request;
                        requestPermissions(new String[]{Manifest.permission.CAMERA}, REQ_CAMARA);
                    }
                });
            }

            @Override
            public void onGeolocationPermissionsShowPrompt(String origin, GeolocationPermissions.Callback callback) {
                if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                    callback.invoke(origin, true, false);
                } else {
                    ubicacionOrigen = origin;
                    ubicacionCallback = callback;
                    requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION}, REQ_UBICACION);
                }
            }

            // Enlaces que abren ventana nueva (WhatsApp, Facebook, privacidad…): se abren fuera de la app.
            @Override
            public boolean onCreateWindow(WebView view, boolean isDialog, boolean isUserGesture, Message resultMsg) {
                WebView temporal = new WebView(MainActivity.this);
                temporal.setWebViewClient(new WebViewClient() {
                    @Override
                    public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                        abrirFuera(r.getUrl());
                        v.destroy();
                        return true;
                    }
                });
                WebView.WebViewTransport transporte = (WebView.WebViewTransport) resultMsg.obj;
                transporte.setWebView(temporal);
                resultMsg.sendToTarget();
                return true;
            }
        });

        web.loadUrl(urlInicial(getIntent()));
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        String ruta = intent.getStringExtra("ruta");
        Uri datos = intent.getData();
        if (ruta != null || datos != null) web.loadUrl(urlInicial(intent));
    }

    /** Link de invitación, o la sección que trae el aviso tocado, o el inicio. */
    private String urlInicial(Intent intent) {
        Uri datos = intent != null ? intent.getData() : null;
        if (datos != null && esPropio(datos)) return datos.toString();
        String ruta = intent != null ? intent.getStringExtra("ruta") : null;
        if (ruta != null && ruta.matches("[a-zA-Z0-9_-]{1,40}")) return APP + "#" + ruta;
        return APP;
    }

    private boolean esPropio(Uri u) {
        String h = u.getHost();
        return "https".equals(u.getScheme()) && h != null && (h.equals(HOST) || h.endsWith("." + HOST));
    }

    private void abrirFuera(Uri u) {
        try {
            Intent i = new Intent(Intent.ACTION_VIEW, u);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (ActivityNotFoundException ignored) {
        }
    }

    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) web.goBack();
        else super.onBackPressed();
    }

    /* ---------- Avisos push ---------- */

    private class Puente {
        @JavascriptInterface
        public void postMessage(String mensaje) {
            runOnUiThread(() -> {
                if ("avisos".equals(mensaje)) pedirAvisos();
                else if ("listo".equals(mensaje)) enviarToken();
            });
        }
    }

    private boolean avisosPermitidos() {
        return Build.VERSION.SDK_INT < 33
                || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED;
    }

    private void pedirAvisos() {
        if (avisosPermitidos()) obtenerToken();
        else requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, REQ_AVISOS);
    }

    private void obtenerToken() {
        FirebaseMessaging.getInstance().getToken().addOnSuccessListener(t -> {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("token", t).apply();
            enviarToken();
        });
    }

    /** Entrega el token a la web; la web lo guarda en la cuenta si la persona ya inició sesión. */
    private void enviarToken() {
        if (web == null) return;
        SharedPreferences p = getSharedPreferences(PREFS, MODE_PRIVATE);
        String t = p.getString("token", null);
        if (t == null) {
            if (avisosPermitidos()) obtenerToken();
            return;
        }
        if (!avisosPermitidos() || !t.matches("[A-Za-z0-9:_-]{20,400}")) return;
        web.evaluateJavascript("window.recibirTokenNativo&&window.recibirTokenNativo('" + t + "')", null);
    }

    /* ---------- Permisos y archivos ---------- */

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        boolean ok = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        if (requestCode == REQ_AVISOS) {
            if (ok) obtenerToken();
            else web.evaluateJavascript("window.avisosDenegados&&window.avisosDenegados()", null);
        } else if (requestCode == REQ_CAMARA && pedidoCamara != null) {
            if (ok) pedidoCamara.grant(pedidoCamara.getResources());
            else pedidoCamara.deny();
            pedidoCamara = null;
        } else if (requestCode == REQ_UBICACION && ubicacionCallback != null) {
            ubicacionCallback.invoke(ubicacionOrigen, ok, false);
            ubicacionCallback = null;
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQ_ARCHIVO && archivos != null) {
            archivos.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data));
            archivos = null;
        }
    }
}
