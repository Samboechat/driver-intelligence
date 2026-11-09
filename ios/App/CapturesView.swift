import SwiftUI
import DriverCore

/// Galeria dos prints de cada chamado.
struct CapturesView: View {
    @EnvironmentObject var perms: Permissions
    @State private var records: [OfferRecord] = []
    @State private var saved: Set<String> = []
    @State private var message: String?
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !perms.photosOK {
                        Banner(text: "Sem acesso às Fotos: os prints ficam só aqui. Toque para liberar e enviar ao álbum \"Driver Intelligence\".", color: Palette.warning)
                            .onTapGesture {
                                if PhotoAlbum.notDetermined { Task { await perms.requestPhotos(); reload() } } else { perms.openAppSettings() }
                            }
                    }
                    if let message { Banner(text: message, color: Palette.positive) }
                    if records.isEmpty {
                        Text("Os prints dos chamados aparecem aqui assim que a leitura de tela estiver ligada e um chamado surgir.")
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 30)
                    }
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(records) { r in
                            NavigationLink { CaptureDetail(record: r) } label: { Thumb(record: r, inPhotos: saved.contains(r.screenshot ?? "")) }
                        }
                    }
                }
                .padding(16)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Prints")
            .toolbar {
                if perms.photosOK && !PhotoAlbum.pending.isEmpty {
                    Button("Enviar ao Fotos") {
                        DispatchQueue.global().async {
                            let n = PhotoAlbum.flushPending()
                            DispatchQueue.main.async {
                                message = n > 0 ? "\(n) print(s) enviados ao álbum Driver Intelligence." : "Nada novo para enviar."
                                reload()
                            }
                        }
                    }
                }
            }
            .refreshable { reload() }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        records = SharedStore.history.filter { r in
            guard let s = r.screenshot else { return false }
            return FileManager.default.fileExists(atPath: SharedStore.screenshotURL(s).path)
        }
        saved = SharedStore.savedToPhotos
    }
}

private struct Thumb: View {
    var record: OfferRecord
    var inPhotos: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ScreenshotImage(name: record.screenshot, maxPixel: 300)
                .aspectRatio(0.48, contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(Br.money(record.fare)).font(.caption.bold().monospacedDigit())
                Text(record.date, style: .time).font(.caption2)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                if inPhotos { Image(systemName: "photo.fill").font(.system(size: 9)) }
                Circle().fill(record.cls.color).frame(width: 9, height: 9)
            }
            .padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(record.cls.color.opacity(0.5), lineWidth: 1))
    }
}

struct ScreenshotImage: View {
    var name: String?
    var maxPixel: CGFloat = 0
    var body: some View {
        if let name, let img = Self.load(name, maxPixel: maxPixel) {
            Image(uiImage: img).resizable()
        } else {
            Rectangle().fill(Palette.surface).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }

    static func load(_ name: String, maxPixel: CGFloat) -> UIImage? {
        let url = SharedStore.screenshotURL(name)
        guard maxPixel > 0 else { return UIImage(contentsOfFile: url.path) }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct CaptureDetail: View {
    var record: OfferRecord
    @State private var inPhotos = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    HStack {
                        Text(Br.money(record.fare)).font(.system(size: 30, weight: .bold).monospacedDigit())
                        Spacer()
                        Pill(text: record.verdict ?? record.cls.shortLabel, color: record.cls.color)
                    }
                    Text(record.headline).font(.subheadline).foregroundStyle(record.cls.color)
                    if let alert = record.alert {
                        Text("⚠️ \(alert)").font(.footnote.weight(.semibold)).foregroundStyle(Palette.warning)
                    }
                    HStack {
                        Stat(title: "R$/km", value: Br.decimal(record.revenuePerKm))
                        Stat(title: "R$/h", value: Br.decimal(record.revenuePerHour, 0))
                        Stat(title: "Lucro", value: Br.money(record.profit))
                    }
                    Text([record.category, Br.km(record.totalKm), record.realisticMin.map { "~\(Br.minutes($0)) real" } ?? Br.minutes(record.totalMin), record.result?.label]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary)
                    if let o = record.origin { Text("Embarque: \(o)").font(.caption).foregroundStyle(.secondary) }
                    if let d = record.destination { Text("Destino: \(d)").font(.caption).foregroundStyle(.secondary) }
                }
                if record.screenshot != nil {
                    ScreenshotImage(name: record.screenshot)
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                HStack {
                    if let s = record.screenshot {
                        ShareLink(item: SharedStore.screenshotURL(s)) {
                            Label("Compartilhar", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            DispatchQueue.global().async {
                                let ok = !PhotoAlbum.save([s]).isEmpty
                                DispatchQueue.main.async { inPhotos = ok || inPhotos }
                            }
                        } label: {
                            Label(inPhotos ? "No álbum" : "Salvar no Fotos", systemImage: inPhotos ? "checkmark" : "photo.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(inPhotos)
                    }
                }
            }
            .padding(16)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(record.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { inPhotos = record.screenshot.map { SharedStore.savedToPhotos.contains($0) } ?? false }
    }
}
