import SwiftUI

/// Cuenta: privacidad y ELIMINAR MIS DATOS dentro de la app (Apple lo exige cuando hay cuentas de cliente).
struct CuentaView: View {
    private let privacidad = URL(string: "https://xdecuador.com/privacidad.html")!
    private let eliminar   = URL(string: "https://xdecuador.com/eliminar-datos.html")!
    private let web        = URL(string: "https://xdecuador.com")!

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image("LogoBlanco")
                            .resizable().scaledToFit()
                            .frame(width: 34, height: 58)
                            .padding(10)
                            .background(Marca.rojo)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bodega XD").font(.system(size: 18, weight: .bold))
                            Text("Tus premios y tus pedidos están en la pestaña Pedir.")
                                .font(.system(size: 13)).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Tus datos") {
                    Link("Política de privacidad", destination: privacidad)
                    Link("Eliminar mis datos", destination: eliminar)
                        .foregroundColor(Marca.rojo)
                }
                Section {
                    Link("xdecuador.com", destination: web)
                    HStack {
                        Text("Versión")
                        Spacer()
                        Text(version).foregroundColor(.secondary)
                    }
                } footer: {
                    Text("XD es nombre comercial de Botaniker Alchemist S.A.S. · RUC 0195101515001")
                }
            }
            .navigationTitle("Cuenta")
        }
    }
}
