import AVFoundation
import Dependencies
import Foundation
import UniformTypeIdentifiers

struct ImportedAudio: Equatable {
    var originalURL: URL
    var localURL: URL
    var title: String
    var duration: TimeInterval?
}

struct AudioImportClient: Sendable {
    var importMedia: @Sendable (URL) async throws -> ImportedAudio
}

extension AudioImportClient {
    static var live: Self {
        Self { url in
            try await AudioImportService.importMedia(from: url)
        }
    }

    static var preview: Self {
        Self { url in
            ImportedAudio(
                originalURL: url,
                localURL: url,
                title: url.deletingPathExtension().lastPathComponent,
                duration: nil
            )
        }
    }
}

extension AudioImportClient: DependencyKey {
    static let liveValue = AudioImportClient.live
    static let previewValue = AudioImportClient.preview
}

extension DependencyValues {
    var audioImportClient: AudioImportClient {
        get { self[AudioImportClient.self] }
        set { self[AudioImportClient.self] = newValue }
    }
}

enum AudioImportError: LocalizedError {
    case unsupportedFormat(String)
    case failedToAccessSecurityScopedResource

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(extensionName):
            return "Unsupported media format: \(extensionName)"
        case .failedToAccessSecurityScopedResource:
            return "Privy could not access the selected file."
        }
    }
}

enum AudioImportService {
    private static let supportedAudioExtensions = ["mp3", "m4a", "wav", "aiff", "caf"]
    private static let supportedVideoExtensions = ["mp4", "mov", "m4v"]

    static func importMedia(from sourceURL: URL) async throws -> ImportedAudio {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileExtension = sourceURL.pathExtension.lowercased()
        guard supportedAudioExtensions.contains(fileExtension)
            || supportedVideoExtensions.contains(fileExtension)
        else {
            throw AudioImportError.unsupportedFormat(fileExtension.isEmpty ? "unknown" : fileExtension)
        }

        let importDirectory = try importedMediaDirectory()
        let baseName = sanitizedFileName(sourceURL.deletingPathExtension().lastPathComponent)

        if supportedVideoExtensions.contains(fileExtension) {
            let destination = uniqueURL(
                in: importDirectory,
                baseName: baseName,
                extension: "m4a"
            )
            try await extractAudio(from: sourceURL, to: destination)
            return ImportedAudio(
                originalURL: sourceURL,
                localURL: destination,
                title: baseName,
                duration: try? await mediaDuration(for: destination)
            )
        }

        let destination = uniqueURL(
            in: importDirectory,
            baseName: baseName,
            extension: fileExtension
        )
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return ImportedAudio(
            originalURL: sourceURL,
            localURL: destination,
            title: baseName,
            duration: try? await mediaDuration(for: destination)
        )
    }

    private static func importedMediaDirectory() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Imported Media", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func uniqueURL(in directory: URL, baseName: String, extension fileExtension: String) -> URL {
        var candidate = directory
            .appendingPathComponent(baseName)
            .appendingPathExtension(fileExtension)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName)-\(index)")
                .appendingPathExtension(fileExtension)
            index += 1
        }
        return candidate
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Imported Audio" : cleaned
    }

    private static func extractAudio(from sourceURL: URL, to destinationURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioImportError.unsupportedFormat(sourceURL.pathExtension)
        }

        try await exportSession.export(to: destinationURL, as: .m4a)
    }

    private static func mediaDuration(for url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }
}
