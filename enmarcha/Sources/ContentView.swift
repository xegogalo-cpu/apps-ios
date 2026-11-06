import SwiftUI
import WebKit

// En Marcha · red de militancia para iPhone (versión nativa con avisos push)
// Abre en-marcha-red.web.app dentro de la app, con:
//  · avisos push nativos: la web pide permiso con el mensaje "avisos" y recibe el token en recibirTokenNativo
//  · ubicación para registrar actividades en el mapa
//  · cámara para el código de asistencia y fotos de actividades y actas
//  · llamadas, WhatsApp y correo se abren en su app propia
//  · deslizar hacia abajo para recargar; si no hay internet, botón Reintentar

let APP_URL = URL(string: "https://en-marcha-red.web.app/?app=ios")!
let NAVY = Color(red: 27/255, green: 35/255, blue: 71/255)      // #1B2347
let ROJO = Color(red: 240/255, green: 69/255, blue: 43/255)     // #F0452B

// Dominios que se quedan dentro de la app (el resto se abre afuera)
let DOMINIOS_PROPIOS = ["en-marcha-red.web.app", "en-marcha-red.firebaseapp.com", "googleapis.com", "gstatic.com",
                        "cloudfunctions.net", "run.app", "cdnjs.cloudflare.com", "openstreetmap.org",
                        "accounts.google.com", "google.com", "googleusercontent.com"]

// Google no deja iniciar sesión desde vistas web incrustadas; con el agente de Safari sí.
// Se agrega la marca EnMarcha-iOS para que la web sepa que corre dentro de la app nativa.
let AGENTE = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1 EnMarcha-iOS/1.2 nativo"

struct ContentView: View {
    @StateObject private var web = WebEstado()
    @ObservedObject private var avisos = Avisos.compartido

    var body: some View {
        contenido
            .onChange(of: avisos.token) { _ in web.enviarToken() }
            .onChange(of: avisos.rutaPendiente) { r in
                guard let r = r else { return }
                web.ejecutar("location.hash='\(r.replacingOccurrences(of: "'", with: ""))'")
                avisos.rutaPendiente = nil
            }
    }

    var contenido: some View {
        ZStack {
            NAVY.ignoresSafeArea()
            MarchaWebView(estado: web)
                .ignoresSafeArea(edges: .bottom)
            if web.cargando && !web.cargoUnaVez {
                VStack(spacing: 14) {
                    Text("En Marcha")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    HStack(spacing: 0) {
                        ForEach([Color(red: 22/255, green: 160/255, blue: 230/255), Color(red: 34/255, green: 172/255, blue: 64/255),
                                 Color(red: 1, green: 213/255, blue: 0), Color(red: 240/255, green: 124/255, blue: 0),
                                 Color(red: 234/255, green: 53/255, blue: 80/255)], id: \.self) { c in
                            Rectangle().fill(c).frame(width: 36, height: 6)
                        }
                    }
                    ProgressView().tint(.white)
                }
            }
            if web.sinInternet {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.slash").font(.system(size: 44))
                    Text("No hay conexión").font(.title2.bold())
                    Text("Revisa tu internet y vuelve a intentar.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Button("Reintentar") { web.recargar() }
                        .buttonStyle(.borderedProminent)
                        .tint(ROJO)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
    }
}

final class WebEstado: ObservableObject {
    @Published var cargando = true
    @Published var cargoUnaVez = false
    @Published var sinInternet = false
    weak var webView: WKWebView?

    func recargar() {
        sinInternet = false
        if let w = webView {
            if w.url == nil { w.load(URLRequest(url: APP_URL)) } else { w.reload() }
        }
    }
    func ejecutar(_ js: String) { webView?.evaluateJavaScript(js, completionHandler: nil) }
    // Entrega a la web el token de avisos; la web lo guarda cuando la persona ya inició sesión.
    func enviarToken() {
        guard let t = Avisos.compartido.token, t.allSatisfy({ $0.isLetter || $0.isNumber || ":_-".contains($0) }) else { return }
        ejecutar("window.recibirTokenNativo&&window.recibirTokenNativo('\(t)')")
    }
}

func esPropio(_ host: String) -> Bool {
    host.isEmpty || DOMINIOS_PROPIOS.contains { host == $0 || host.hasSuffix("." + $0) }
}

struct MarchaWebView: UIViewRepresentable {
    @ObservedObject var estado: WebEstado

    func makeCoordinator() -> Coordinador { Coordinador(estado: estado) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()                   // mantiene la sesión iniciada
        config.preferences.javaScriptCanOpenWindowsAutomatically = true  // ventana de Google
        config.userContentController.add(context.coordinator, name: "enmarcha")
        let w = WKWebView(frame: .zero, configuration: config)
        w.customUserAgent = AGENTE
        w.navigationDelegate = context.coordinator
        w.uiDelegate = context.coordinator
        w.allowsBackForwardNavigationGestures = true
        w.scrollView.contentInsetAdjustmentBehavior = .automatic
        w.isOpaque = false
        w.backgroundColor = UIColor(red: 27/255, green: 35/255, blue: 71/255, alpha: 1)

        let rc = UIRefreshControl()
        rc.addTarget(context.coordinator, action: #selector(Coordinador.refrescar(_:)), for: .valueChanged)
        w.scrollView.refreshControl = rc

        estado.webView = w
        w.load(URLRequest(url: APP_URL))
        return w
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinador: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let estado: WebEstado
        init(estado: WebEstado) { self.estado = estado }

        // Mensajes de la web: "avisos" pide permiso; "listo" avisa que ya hay sesión para guardar el token.
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let m = message.body as? String else { return }
            if m == "avisos" { Avisos.compartido.pedirPermiso() }
            if m == "listo" { estado.enviarToken() }
        }

        @objc func refrescar(_ rc: UIRefreshControl) {
            estado.recargar()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { rc.endRefreshing() }
        }

        // Lo de la app se queda adentro; WhatsApp, tel:, mailto: y enlaces externos se abren afuera
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.allow); return }
            let esquema = url.scheme?.lowercased() ?? ""
            let host = url.host?.lowercased() ?? ""
            if esquema == "http" || esquema == "https" {
                if esPropio(host) || action.targetFrame?.isMainFrame == false {
                    decisionHandler(.allow)
                } else {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                }
            } else if esquema == "about" || esquema == "blob" || esquema == "data" {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            }
        }

        // Enlaces con target=_blank (WhatsApp, Google Maps, enlaces de comunicados): afuera
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            let url = action.request.url
            let host = url?.host?.lowercased() ?? ""
            let vacia = url == nil || url!.absoluteString.isEmpty || url!.absoluteString == "about:blank"
            // WhatsApp, mapas y enlaces externos: afuera. La ventana de inicio con Google: en una hoja encima.
            if !vacia, let u = url, !esPropio(host) {
                UIApplication.shared.open(u)
                return nil
            }
            let hija = WKWebView(frame: .zero, configuration: configuration)
            hija.customUserAgent = AGENTE
            hija.navigationDelegate = self
            hija.uiDelegate = self
            let nav = UINavigationController(rootViewController: VentanaHoja(web: hija))
            nav.modalPresentationStyle = .pageSheet
            presentarVC(nav)
            return hija
        }

        // window.close() al terminar el inicio con Google
        func webViewDidClose(_ webView: WKWebView) {
            var r: UIResponder? = webView
            while let x = r {
                if let vc = x as? VentanaHoja { vc.dismiss(animated: true); return }
                r = x.next
            }
        }

        // Cámara del lector de asistencia: se concede a la propia app (iOS pregunta una vez)
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(esPropio(origin.host.lowercased()) ? .grant : .prompt)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if webView === estado.webView { estado.cargando = true }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView === estado.webView else { return }
            estado.cargando = false
            estado.cargoUnaVez = true
            estado.sinInternet = false
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard webView === estado.webView else { return }
            estado.cargando = false
            if (error as NSError).code != NSURLErrorCancelled { estado.sinInternet = true }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        // prompt() y confirm() de la app (olvidé mi clave, motivo de suspensión, estados)
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            presentar(a, o: completionHandler)
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
            a.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler(true) })
            presentar(a, o: { completionHandler(false) })
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            a.addTextField { $0.text = defaultText }
            a.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(nil) })
            a.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
            presentar(a, o: { completionHandler(nil) })
        }
        private func presentar(_ a: UIAlertController, o fallback: @escaping () -> Void) {
            guard let raiz = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { fallback(); return }
            var top = raiz; while let p = top.presentedViewController { top = p }
            top.present(a, animated: true)
        }
        private func presentarVC(_ vc: UIViewController) {
            guard let raiz = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
            var top = raiz; while let p = top.presentedViewController { top = p }
            top.present(vc, animated: true)
        }
    }
}

// Hoja para la ventana de inicio con Google: se cierra sola al terminar o con el botón Cerrar.
final class VentanaHoja: UIViewController {
    let web: WKWebView
    init(web: WKWebView) { self.web = web; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() { view = web }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "En Marcha"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cerrar", style: .done, target: self, action: #selector(cerrar))
    }
    @objc func cerrar() { dismiss(animated: true) }
}
