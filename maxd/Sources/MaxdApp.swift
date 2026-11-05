import SwiftUI
import WebKit

@main
struct MaxdApp: App {
    @UIApplicationDelegateAdaptor(PushPuente.self) var puente
    var body: some Scene {
        WindowGroup { RaizView() }
    }
}

enum Marca {
    static let coral = Color(red: 0.937, green: 0.361, blue: 0.337)   // #EF5C56, el de maXD
    static let crema = Color(red: 0.969, green: 0.929, blue: 0.867)
    static let sistema = URL(string: "https://maxdec.netlify.app/?app=staff")!
}

/// maXD a pantalla completa: es el mismo sistema que el equipo usa en la caja y en Android.
struct RaizView: View {
    @StateObject private var estado = EstadoWeb()
    var body: some View {
        ZStack {
            Marca.coral.ignoresSafeArea(edges: .top)
            WebSistema(estado: estado).ignoresSafeArea(edges: .bottom)
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

struct WebSistema: UIViewRepresentable {
    @ObservedObject var estado: EstadoWeb
    func makeCoordinator() -> Coordinador { Coordinador(estado: estado) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let marca = WKUserScript(
            source: "try{Object.defineProperty(navigator,'standalone',{get:function(){return true}});}catch(e){}; window.__APP_IOS__=true;",
            injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(marca)
        if let p = PushPuente.actual { config.userContentController.add(p, name: "xdPush") }   // avisos push nativos

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = false
        web.backgroundColor = .white
        web.evaluateJavaScript("navigator.userAgent") { res, _ in
            if let ua = res as? String { web.customUserAgent = ua + " maXD-iOS/2.0" }
            web.load(URLRequest(url: Marca.sistema))
        }
        context.coordinator.web = web
        PushPuente.actual?.web = web
        PushPuente.actual?.base = Marca.sistema
        estado.recargar = { [weak web] in
            DispatchQueue.main.async {
                self.estado.sinConexion = false
                if let w = web { if w.url == nil { w.load(URLRequest(url: Marca.sistema)) } else { w.reload() } }
            }
        }
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinador: NSObject, WKNavigationDelegate, WKUIDelegate {
        let estado: EstadoWeb
        weak var web: WKWebView?
        init(estado: EstadoWeb) { self.estado = estado }

        /// WhatsApp, llamadas, correo, mapas y tiendas se abren en su app.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            let esquema = (url.scheme ?? "").lowercased()
            let host = (url.host ?? "").lowercased()
            let afuera = ["tel", "mailto", "whatsapp", "maps", "comgooglemaps", "itms-apps"].contains(esquema)
                || host.hasSuffix("wa.me") || host.hasSuffix("whatsapp.com") || host.hasSuffix("maps.apple.com")
                || host.hasSuffix("play.google.com") || host.hasSuffix("apps.apple.com")
            if afuera { UIApplication.shared.open(url); decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }

        /// Ventanas nuevas (reportes, impresión, WhatsApp Web): se abren en Safari para no perder la caja.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                if url.absoluteString.isEmpty || url.scheme == "about" { return nil }
                UIApplication.shared.open(url)
            }
            return nil
        }

        /// Cámara y micrófono dentro del sistema (foto de marcación, walkie): se permiten para maXD.
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(origin.host.hasSuffix("maxdec.netlify.app") || origin.host.hasSuffix("xdecuador.com") ? .grant : .prompt)
        }

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
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            a.addTextField { $0.text = defaultText }
            a.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(nil) })
            a.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
            presentar(a) { completionHandler(nil) }
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
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fallo(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fallo(error) }
        private func fallo(_ error: Error) {
            let e = error as NSError
            if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
            if e.domain == NSURLErrorDomain { DispatchQueue.main.async { self.estado.sinConexion = true } }
        }
    }
}

struct SinConexionView: View {
    let reintentar: () -> Void
    var body: some View {
        ZStack {
            Marca.coral.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("maXD").font(.system(size: 44, weight: .black)).foregroundColor(Marca.crema)
                Text("Sin conexión").font(.system(size: 24, weight: .heavy)).foregroundColor(.white)
                Text("Revisa el internet del local y vuelve a intentar.")
                    .font(.system(size: 16, weight: .medium)).foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                Button(action: reintentar) {
                    Text("Reintentar").font(.system(size: 17, weight: .bold)).foregroundColor(Marca.coral)
                        .padding(.horizontal, 36).padding(.vertical, 14)
                        .background(Color.white).clipShape(Capsule())
                }.padding(.top, 6)
            }.padding(32)
        }
    }
}
