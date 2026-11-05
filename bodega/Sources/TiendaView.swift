import SwiftUI
import WebKit

/// La tienda (xdecuador.com) dentro de la app, con lo nativo que Apple pide:
/// recargar deslizando, aviso propio sin conexión, enlaces externos (WhatsApp, llamadas, mapas)
/// abiertos en su app, y la página sabe que está dentro de la app (no ofrece "Descargar la app").
struct TiendaView: View {
    @StateObject private var estado = EstadoWeb()
    var body: some View {
        ZStack {
            Marca.rojo.ignoresSafeArea(edges: .top)
            WebTienda(estado: estado)
                .ignoresSafeArea(edges: .bottom)
            if estado.sinConexion {
                SinConexionView { estado.recargar?() }
            }
        }
    }
}

final class EstadoWeb: ObservableObject {
    @Published var sinConexion = false
    var recargar: (() -> Void)?
}

struct WebTienda: UIViewRepresentable {
    @ObservedObject var estado: EstadoWeb

    func makeCoordinator() -> Coordinador { Coordinador(estado: estado) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // La página trata a la app como "ya instalada": no muestra el botón de descargar.
        let marca = WKUserScript(
            source: "try{Object.defineProperty(navigator,'standalone',{get:function(){return true}});}catch(e){}; window.__APP_IOS__=true;",
            injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(marca)
        if let p = PushPuente.actual { config.userContentController.add(p, name: "xdPush") }   // avisos del pedido

        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = nil
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.scrollView.contentInsetAdjustmentBehavior = .automatic
        web.backgroundColor = UIColor(Marca.crema)
        web.isOpaque = false
        // Se agrega "BodegaXD-iOS" al agente para que la tienda sepa que viene de la app.
        web.evaluateJavaScript("navigator.userAgent") { res, _ in
            if let ua = res as? String { web.customUserAgent = ua + " BodegaXD-iOS/2.0" }
            web.load(URLRequest(url: Marca.tienda))
        }

        let refresco = UIRefreshControl()
        refresco.tintColor = UIColor(Marca.rojo)
        refresco.addTarget(context.coordinator, action: #selector(Coordinador.alRefrescar(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refresco

        context.coordinator.web = web
        PushPuente.actual?.web = web
        PushPuente.actual?.base = Marca.tienda
        estado.recargar = { [weak web] in
            DispatchQueue.main.async {
                self.estado.sinConexion = false
                if let w = web {
                    if w.url == nil { w.load(URLRequest(url: Marca.tienda)) } else { w.reload() }
                }
            }
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinador: NSObject, WKNavigationDelegate, WKUIDelegate {
        let estado: EstadoWeb
        weak var web: WKWebView?
        init(estado: EstadoWeb) { self.estado = estado }

        @objc func alRefrescar(_ sender: UIRefreshControl) {
            web?.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { sender.endRefreshing() }
        }

        /// Lo que no es la tienda se abre afuera: WhatsApp, llamadas, correo, mapas, tiendas de apps.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            let esquema = (url.scheme ?? "").lowercased()
            let host = (url.host ?? "").lowercased()
            let externoEsquema = ["tel", "mailto", "whatsapp", "maps", "comgooglemaps", "itms-apps"].contains(esquema)
            let externoHost = host.hasSuffix("wa.me") || host.hasSuffix("whatsapp.com") ||
                              host.hasSuffix("maps.apple.com") || host.contains("google.com/maps") ||
                              host.hasSuffix("play.google.com") || host.hasSuffix("apps.apple.com") ||
                              host.hasSuffix("instagram.com") || host.hasSuffix("facebook.com") || host.hasSuffix("tiktok.com")
            if externoEsquema || externoHost {
                UIApplication.shared.open(url)
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        /// Enlaces que piden ventana nueva (target=_blank): se abren en la misma vista.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        /// Avisos de la página (alert / confirm) como avisos nativos.
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            presentar(a, sino: completionHandler)
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
            a.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler(true) })
            presentar(a) { completionHandler(false) }
        }
        private func presentar(_ a: UIAlertController, sino: @escaping () -> Void) {
            let escena = UIApplication.shared.connectedScenes.first as? UIWindowScene
            guard let raiz = escena?.windows.first(where: { $0.isKeyWindow })?.rootViewController else { sino(); return }
            var arriba = raiz
            while let p = arriba.presentedViewController { arriba = p }
            arriba.present(a, animated: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.estado.sinConexion = false }
            PushPuente.actual?.paginaLista()
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fallo(error)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fallo(error)
        }
        private func fallo(_ error: Error) {
            let e = error as NSError
            if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
            if e.domain == NSURLErrorDomain {
                DispatchQueue.main.async { self.estado.sinConexion = true }
            }
        }
    }
}

struct SinConexionView: View {
    let reintentar: () -> Void
    var body: some View {
        ZStack {
            Marca.rojo.ignoresSafeArea()
            VStack(spacing: 18) {
                Image("LogoBlanco").resizable().scaledToFit().frame(width: 110)
                Text("Sin conexión")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(Marca.crema)
                Text("Revisa tu internet y vuelve a intentar.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Marca.crema.opacity(0.9))
                Button(action: reintentar) {
                    Text("Reintentar")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Marca.rojo)
                        .padding(.horizontal, 36).padding(.vertical, 14)
                        .background(Marca.crema)
                        .clipShape(Capsule())
                }
                .padding(.top, 6)
            }
            .padding(32)
        }
    }
}
