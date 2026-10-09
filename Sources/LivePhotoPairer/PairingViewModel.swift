import AppKit
import AVFoundation
import CoreMedia
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// State and actions backing the pairing UI.
@MainActor
@Observable
final class PairingViewModel {
    // MARK: Inputs
    var photoURL: URL? { didSet { photoChanged() } }
    var videoURL: URL? { didSet { videoChanged() } }
    var contentIdentifier: String = UUID().uuidString
    /// Fraction (0…1) of the video duration used as the still-image time.
    var stillImageFraction: Double = 0.5
    var outputDirectory: URL?

    // MARK: Derived / inspected info
    var photoInfo: String = ""
    var videoInfo: String = ""
    var videoDurationSeconds: Double = 0
    var existingPhotoIdentifier: String?
    var existingVideoIdentifier: String?
    var photoThumbnail: NSImage?
    var videoThumbnail: NSImage?

    // MARK: Run state
    enum RunState: Equatable {
        case idle
        case running(Double)
        case done(photo: URL, video: URL, validated: Bool)
        case failed(String)
    }
    var runState: RunState = .idle

    var canPair: Bool {
        if case .running = runState { return false }
        return photoURL != nil && videoURL != nil && !contentIdentifier.isEmpty
    }

    var stillImageTimeSeconds: Double { stillImageFraction * videoDurationSeconds }

    var effectiveOutputDirectory: URL? {
        outputDirectory ?? photoURL?.deletingLastPathComponent()
    }

    // MARK: - Input inspection

    private func photoChanged() {
        runState = .idle
        photoThumbnail = nil
        photoInfo = ""
        existingPhotoIdentifier = nil
        guard let url = photoURL else { return }
        existingPhotoIdentifier = LivePhotoPairingEngine.readPhotoContentIdentifier(imageURL: url)
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            let w = props[kCGImagePropertyPixelWidth as String] ?? "?"
            let h = props[kCGImagePropertyPixelHeight as String] ?? "?"
            photoInfo = "\(w) × \(h)"
        }
        if let image = NSImage(contentsOf: url) {
            photoThumbnail = image
        }
        if let existing = existingPhotoIdentifier, !existing.isEmpty {
            contentIdentifier = existing
        }
    }

    private func videoChanged() {
        runState = .idle
        videoThumbnail = nil
        videoInfo = ""
        existingVideoIdentifier = nil
        videoDurationSeconds = 0
        guard let url = videoURL else { return }
        Task {
            let asset = AVURLAsset(url: url)
            async let durationLoad = asset.load(.duration)
            async let idLoad = LivePhotoPairingEngine.readVideoContentIdentifier(videoURL: url)
            async let thumbLoad = Self.generateVideoThumbnail(asset: asset)
            let (duration, identifier, thumb) = await ((try? durationLoad) ?? .zero, idLoad, thumbLoad)
            guard videoURL == url else { return }
            videoDurationSeconds = duration.seconds
            existingVideoIdentifier = identifier
            videoThumbnail = thumb
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize) {
                videoInfo = String(
                    format: "%d × %d · %.2f s",
                    Int(size.width), Int(size.height), duration.seconds
                )
            } else {
                videoInfo = String(format: "%.2f s", duration.seconds)
            }
        }
    }

    private static func generateVideoThumbnail(asset: AVAsset) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: .zero) { cgImage, _, _ in
                if let cgImage {
                    continuation.resume(returning: NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    ))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Actions

    func regenerateIdentifier() {
        contentIdentifier = UUID().uuidString
    }

    func choosePhoto() {
        if let url = Self.openPanel(contentTypes: [.heic, .jpeg, .image]) {
            photoURL = url
        }
    }

    func chooseVideo() {
        if let url = Self.openPanel(contentTypes: [.movie, .quickTimeMovie, .mpeg4Movie]) {
            videoURL = url
        }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK {
            outputDirectory = panel.url
        }
    }

    private static func openPanel(contentTypes: [UTType]) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    func handleDrop(_ providers: [NSItemProvider], isPhoto: Bool) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                if isPhoto { self.photoURL = url } else { self.videoURL = url }
            }
        }
        return true
    }

    // MARK: - Pairing

    func pair() {
        guard let photoURL, let videoURL, let outDir = effectiveOutputDirectory else { return }
        let baseName = photoURL.deletingPathExtension().lastPathComponent
        let photoExt = photoURL.pathExtension
        let outPhoto = outDir.appendingPathComponent("\(baseName)_paired.\(photoExt)")
        let outVideo = outDir.appendingPathComponent("\(baseName)_paired.mov")

        let identifier = contentIdentifier
        let stillTime = CMTime(
            seconds: stillImageFraction * videoDurationSeconds,
            preferredTimescale: 600
        )
        let options = LivePhotoPairingEngine.PairingOptions(
            contentIdentifier: identifier,
            stillImageTime: stillTime,
            creationDate: Date()
        )

        runState = .running(0)
        Task {
            do {
                let result = try await LivePhotoPairingEngine.pair(
                    photo: photoURL,
                    video: videoURL,
                    outputPhotoURL: outPhoto,
                    outputVideoURL: outVideo,
                    options: options
                ) { [weak self] p in
                    Task { @MainActor in self?.runState = .running(p) }
                }
                let validation = await LivePhotoPairingEngine.validate(
                    photoURL: result.photoURL,
                    videoURL: result.videoURL,
                    expectedIdentifier: identifier
                )
                runState = .done(
                    photo: result.photoURL,
                    video: result.videoURL,
                    validated: validation.photoOK && validation.videoOK
                )
            } catch {
                runState = .failed(error.localizedDescription)
            }
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
