import SwiftUI

@main
struct BodegaXDApp: App {
    @UIApplicationDelegateAdaptor(PushPuente.self) var puente
    var body: some Scene {
        WindowGroup {
            RaizView()
        }
    }
}

/// Colores de la marca (los mismos de xdecuador.com).
enum Marca {
    static let rojo  = Color(red: 0.890, green: 0.122, blue: 0.118)   // #E31F1E
    static let crema = Color(red: 0.988, green: 0.980, blue: 0.969)   // #FCFAF7
    static let tinta = Color(red: 0.133, green: 0.118, blue: 0.106)   // #221E1B
    static let tienda = URL(string: "https://xdecuador.com/?app=tienda")!
}

/// Pantalla de inicio roja con el logo, y después las pestañas.
struct RaizView: View {
    @State private var listo = false
    var body: some View {
        ZStack {
            PestanasView()
            if !listo {
                PantallaCarga()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            withAnimation(.easeOut(duration: 0.35)) { listo = true }
        }
    }
}

struct PantallaCarga: View {
    @State private var escala: CGFloat = 0.7
    var body: some View {
        ZStack {
            Marca.rojo.ignoresSafeArea()
            Image("LogoBlanco")
                .resizable()
                .scaledToFit()
                .frame(width: 150)
                .scaleEffect(escala)
                .onAppear {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) { escala = 1.0 }
                }
        }
    }
}

struct PestanasView: View {
    var body: some View {
        TabView {
            TiendaView()
                .tabItem { Label("Pedir", systemImage: "bag.fill") }
            LocalesView()
                .tabItem { Label("Locales", systemImage: "mappin.and.ellipse") }
            CuentaView()
                .tabItem { Label("Cuenta", systemImage: "person.crop.circle") }
        }
        .tint(Marca.rojo)
    }
}
