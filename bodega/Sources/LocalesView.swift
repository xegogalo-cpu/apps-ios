import SwiftUI

/// Locales en una pantalla nativa: cómo llegar (Mapas de Apple) y escribirnos por WhatsApp.
struct Local: Identifiable {
    let id = UUID()
    let nombre: String
    let detalle: String
    let busquedaMapa: String
}

struct LocalesView: View {
    private let locales: [Local] = [
        Local(nombre: "Bodega XD+ · Puertas del Sol", detalle: "Hamburguesas, pollito y promos del día",
              busquedaMapa: "Bodega XD Puertas del Sol Cuenca"),
        Local(nombre: "Bodega XD & Mañuka · El Vergel", detalle: "Hamburguesas y waffles de yuca",
              busquedaMapa: "Bodega XD El Vergel Cuenca"),
        Local(nombre: "Mañuka · Centro Histórico", detalle: "Waffles de yuca",
              busquedaMapa: "Mañuka Centro Histórico Cuenca")
    ]
    private let whatsapp = URL(string: "https://wa.me/593986998511")!

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(locales) { l in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(l.nombre).font(.system(size: 17, weight: .bold))
                            Text(l.detalle).font(.system(size: 14)).foregroundColor(.secondary)
                            Button {
                                abrirMapa(l.busquedaMapa)
                            } label: {
                                Label("Cómo llegar", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .buttonStyle(.borderless)
                            .tint(Marca.rojo)
                        }
                        .padding(.vertical, 6)
                    }
                }
                Section {
                    Link(destination: whatsapp) {
                        Label("Escríbenos por WhatsApp", systemImage: "message.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .tint(Marca.rojo)
                }
            }
            .navigationTitle("Locales")
        }
    }

    private func abrirMapa(_ q: String) {
        let texto = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        if let url = URL(string: "https://maps.apple.com/?q=\(texto)") { UIApplication.shared.open(url) }
    }
}
