import UIKit
import UserNotifications
import WebKit

/// Puente de avisos push entre iOS (APNs) y la página de maXD / la tienda Bodega XD.
/// La página llama `webkit.messageHandlers.xdPush.postMessage({accion:'pedir'|'estado'})`
/// y recibe `window.__xdPushNativo({permiso, token, bundle, env})`.
/// Al tocar un aviso se abre la dirección que trae (`url`) dentro de la app.
final class PushPuente: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, WKScriptMessageHandler {
    static private(set) var actual: PushPuente?
    weak var web: WKWebView?
    var base: URL = URL(string: "https://xdecuador.com/")!
    private(set) var token: String?
    private var urlPendiente: URL?

    override init() {
        super.init()
        PushPuente.actual = self
    }

    #if DEBUG
    private let entorno = "development"
    #else
    private let entorno = "production"
    #endif

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Si ya dio permiso antes, se registra en silencio para tener el token al día.
        UNUserNotificationCenter.current().getNotificationSettings { s in
            if s.authorizationStatus == .authorized || s.authorizationStatus == .provisional || s.authorizationStatus == .ephemeral {
                DispatchQueue.main.async { application.registerForRemoteNotifications() }
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        avisarPagina()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        avisarPagina()
    }

    // MARK: - Página → iOS
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let accion = (message.body as? [String: Any])?["accion"] as? String ?? "estado"
        if accion == "pedir" {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                DispatchQueue.main.async {
                    if ok { UIApplication.shared.registerForRemoteNotifications() }
                    self.avisarPagina()
                }
            }
        } else {
            avisarPagina()
        }
    }

    /// iOS → página: permiso y token actuales.
    func avisarPagina() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let permiso: String
            switch s.authorizationStatus {
            case .authorized, .provisional, .ephemeral: permiso = "granted"
            case .denied: permiso = "denied"
            default: permiso = "default"
            }
            let bundle = Bundle.main.bundleIdentifier ?? ""
            let tok = self.token.map { "'\($0)'" } ?? "null"
            let js = "window.__xdPushNativo && window.__xdPushNativo({permiso:'\(permiso)', token:\(tok), bundle:'\(bundle)', env:'\(self.entorno)'});"
            DispatchQueue.main.async { self.web?.evaluateJavaScript(js, completionHandler: nil) }
        }
    }

    /// La página terminó de cargar: se le cuenta el estado y se abre el aviso que estaba esperando.
    func paginaLista() {
        avisarPagina()
        if let u = urlPendiente { urlPendiente = nil; web?.load(URLRequest(url: u)) }
    }

    /// "./" solo abre la app; "#walkie" o "./#walkie" va a esa parte del sistema; "/?app=tienda#seguir-…" al seguimiento.
    private func destino(_ s: String) -> URL? {
        if s.isEmpty || s == "./" || s == "/" { return nil }
        if s.hasPrefix("#") || s.hasPrefix("./#") {
            var c = URLComponents(url: base, resolvingAgainstBaseURL: false)
            c?.fragment = String(s.drop(while: { $0 != "#" }).dropFirst())
            return c?.url
        }
        return URL(string: s, relativeTo: base)?.absoluteURL
    }

    // MARK: - Avisos
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let s = info["url"] as? String, let u = destino(s), let host = u.host, host == base.host {
            // Un parámetro nuevo obliga a abrir la página de nuevo: si solo cambiara lo que va después de "#",
            // la tienda no volvería a leer a qué pedido ir.
            var c = URLComponents(url: u, resolvingAgainstBaseURL: false)
            var q = c?.queryItems ?? []
            q.append(URLQueryItem(name: "av", value: String(Int(Date().timeIntervalSince1970))))
            c?.queryItems = q
            let destinoFinal = c?.url ?? u
            if let w = web, w.url != nil { w.load(URLRequest(url: destinoFinal)) } else { urlPendiente = destinoFinal }
        }
        completionHandler()
    }
}
