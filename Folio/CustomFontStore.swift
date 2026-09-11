import Combine
import CoreText
import Foundation
import ReadiumNavigator
import ReadiumShared

struct ImportedFont: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let fileName: String
}

@MainActor
final class CustomFontStore: ObservableObject {
    static let shared = CustomFontStore()

    @Published private(set) var fonts: [ImportedFont] = []

    private let manifestName = "ImportedFonts.json"

    private init() {
        createFontsDirectoryIfNeeded()
        load()
        registerSavedFonts()
    }

    func importFont(from sourceURL: URL) throws {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileExtension = sourceURL.pathExtension.lowercased()
        guard ["otf", "ttf", "ttc"].contains(fileExtension) else {
            throw CustomFontError.unsupportedFormat
        }

        let fileName = UUID().uuidString + "." + fileExtension
        let destinationURL = fontsDirectory.appending(path: fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        do {
            guard let descriptor = fontDescriptors(at: destinationURL).first,
                  let postScriptName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
            else {
                throw CustomFontError.unreadableFont
            }

            let familyName = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
                ?? postScriptName

            var registrationError: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(
                destinationURL as CFURL,
                .process,
                &registrationError
            )

            guard registered || UIFontNameChecker.isAvailable(postScriptName) else {
                throw registrationError?.takeRetainedValue() ?? CustomFontError.registrationFailed
            }

            guard !fonts.contains(where: { $0.id == postScriptName }) else {
                throw CustomFontError.alreadyImported
            }

            fonts.append(
                ImportedFont(id: postScriptName, displayName: familyName, fileName: fileName)
            )
            fonts.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            save()
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    func remove(_ font: ImportedFont) {
        let url = fontsDirectory.appending(path: font.fileName)
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        try? FileManager.default.removeItem(at: url)
        fonts.removeAll { $0.id == font.id }
        save()
    }

    func displayName(for identifier: String) -> String? {
        fonts.first { $0.id == identifier }?.displayName
    }

    var readiumDeclarations: [AnyHTMLFontFamilyDeclaration] {
        fonts.compactMap { font in
            let url = fontsDirectory.appending(path: font.fileName)
            guard let fileURL = FileURL(url: url) else { return nil }

            return CSSFontFamilyDeclaration(
                fontFamily: FontFamily(rawValue: font.id),
                fontFaces: [CSSFontFace(file: fileURL)]
            )
            .eraseToAnyHTMLFontFamilyDeclaration()
        }
    }

    private var fontsDirectory: URL {
        URL.documentsDirectory.appending(path: "Fonts", directoryHint: .isDirectory)
    }

    private var manifestURL: URL {
        fontsDirectory.appending(path: manifestName)
    }

    private func createFontsDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: fontsDirectory, withIntermediateDirectories: true)
    }

    private func fontDescriptors(at url: URL) -> [CTFontDescriptor] {
        CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
    }

    private func registerSavedFonts() {
        for font in fonts {
            let url = fontsDirectory.appending(path: font.fileName)
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let savedFonts = try? JSONDecoder().decode([ImportedFont].self, from: data)
        else {
            return
        }
        fonts = savedFonts
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(fonts) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}

private enum UIFontNameChecker {
    static func isAvailable(_ name: String) -> Bool {
        let font = CTFontCreateWithName(name as CFString, 16, nil)
        return CTFontCopyPostScriptName(font) as String == name
    }
}

private enum CustomFontError: LocalizedError {
    case unsupportedFormat
    case unreadableFont
    case registrationFailed
    case alreadyImported

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "Choose an OpenType or TrueType font file."
        case .unreadableFont:
            "Folio couldn’t read that font file."
        case .registrationFailed:
            "Folio couldn’t register that font."
        case .alreadyImported:
            "That font is already in Folio."
        }
    }
}
