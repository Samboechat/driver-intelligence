import Foundation
import Photos

/// Álbum "Driver Intelligence" no app Fotos, onde ficam os prints de cada chamado.
enum PhotoAlbum {
    static let title = "Driver Intelligence"

    static var readWrite: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    static var addOnly: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .addOnly) }

    /// Pode gravar fotos (acesso total, limitado ou "só adicionar").
    static var canAdd: Bool {
        [.authorized, .limited].contains(readWrite) || addOnly == .authorized
    }

    /// Pode organizar num álbum próprio (precisa de leitura).
    static var canUseAlbum: Bool { [.authorized, .limited].contains(readWrite) }

    static var notDetermined: Bool { readWrite == .notDetermined && addOnly == .notDetermined }

    static func requestAccess(_ done: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
            if s == .authorized || s == .limited { return done(true) }
            // Se negar o acesso total, ainda pedimos o "só adicionar".
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { s2 in done(s2 == .authorized) }
        }
    }

    private static func existingAlbum() -> PHAssetCollection? {
        if let id = SharedStore.albumId,
           let a = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
            return a
        }
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "title = %@", title)
        let found = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: opts).firstObject
        if let found { SharedStore.albumId = found.localIdentifier }
        return found
    }

    private static func album() -> PHAssetCollection? {
        guard canUseAlbum else { return nil }
        if let a = existingAlbum() { return a }
        var id: String?
        try? PHPhotoLibrary.shared().performChangesAndWait {
            id = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                .placeholderForCreatedAssetCollection.localIdentifier
        }
        if let id { SharedStore.albumId = id }
        return id.flatMap { PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [$0], options: nil).firstObject }
    }

    /// Grava os arquivos no Fotos (no álbum, quando possível). Devolve os nomes gravados.
    @discardableResult
    static func save(_ names: [String]) -> Set<String> {
        guard canAdd, !names.isEmpty else { return [] }
        let files = names.map { ($0, SharedStore.screenshotURL($0)) }
            .filter { FileManager.default.fileExists(atPath: $0.1.path) }
        guard !files.isEmpty else { return [] }
        let target = album()
        do {
            try PHPhotoLibrary.shared().performChangesAndWait {
                var placeholders: [PHObjectPlaceholder] = []
                for (_, url) in files {
                    if let p = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)?.placeholderForCreatedAsset {
                        placeholders.append(p)
                    }
                }
                if let target, let change = PHAssetCollectionChangeRequest(for: target) {
                    change.addAssets(placeholders as NSArray)
                }
            }
        } catch {
            return []
        }
        let done = Set(files.map(\.0))
        SharedStore.savedToPhotos = SharedStore.savedToPhotos.union(done)
        return done
    }

    /// Prints que ainda não foram para o Fotos.
    static var pending: [String] {
        let saved = SharedStore.savedToPhotos
        let names = SharedStore.history.compactMap(\.screenshot)
        return Array(Set(names).subtracting(saved)).sorted()
    }

    /// Envia os pendentes (chamado pelo app ao abrir e periodicamente).
    static func flushPending() -> Int {
        let p = pending
        guard !p.isEmpty, SharedStore.settings.saveScreenshots else { return 0 }
        var total = 0
        for chunk in stride(from: 0, to: p.count, by: 20).map({ Array(p[$0..<min($0 + 20, p.count)]) }) {
            total += save(chunk).count
        }
        return total
    }
}
