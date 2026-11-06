import SwiftUI
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

// Avisos push nativos: Apple entrega el aviso, Firebase da el token que guarda la web en privado/{uid}.tokens.
final class Avisos: NSObject, ObservableObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    static let compartido = Avisos()
    @Published var token: String?
    @Published var rutaPendiente: String?

    func pedirPermiso() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { ok, _ in
            guard ok else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }
    // Si ya dio permiso antes, se registra solo al abrir la app.
    func registrarSiYaPermitio() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            guard s.authorizationStatus == .authorized else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        DispatchQueue.main.async { self.token = fcmToken }
    }
    // Con la app abierta, el aviso también se muestra arriba.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    // Al tocar el aviso, la app abre la sección que corresponde.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let ruta = response.notification.request.content.userInfo["ruta"] as? String ?? "inicio"
        DispatchQueue.main.async { self.rutaPendiente = ruta }
        completionHandler()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = Avisos.compartido
        Messaging.messaging().delegate = Avisos.compartido
        Avisos.compartido.registrarSiYaPermitio()
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
}

@main
struct EnMarchaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegado

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
