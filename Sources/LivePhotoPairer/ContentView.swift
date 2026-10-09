import SwiftUI

struct ContentView: View {
    @State private var model = PairingViewModel()

    var body: some View {
        VStack(spacing: 16) {
            header
            HStack(spacing: 16) {
                InputCard(
                    title: "照片 Photo",
                    systemImage: "photo",
                    url: model.photoURL,
                    info: model.photoInfo,
                    existingIdentifier: model.existingPhotoIdentifier,
                    thumbnail: model.photoThumbnail,
                    onChoose: model.choosePhoto,
                    onDrop: { model.handleDrop($0, isPhoto: true) }
                )
                Image(systemName: "link")
                    .font(.title)
                    .foregroundStyle(.secondary)
                InputCard(
                    title: "视频 Video",
                    systemImage: "video",
                    url: model.videoURL,
                    info: model.videoInfo,
                    existingIdentifier: model.existingVideoIdentifier,
                    thumbnail: model.videoThumbnail,
                    onChoose: model.chooseVideo,
                    onDrop: { model.handleDrop($0, isPhoto: false) }
                )
            }
            .frame(maxHeight: .infinity)

            settingsSection
            actionSection
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 600)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Live Photo Pairer")
                .font(.title.bold())
            Text("将任意 HEIC 照片与 MOV 视频配对为一张 Live Photo · Pair any HEIC + MOV into a Live Photo")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var settingsSection: some View {
        GroupBox("配对设置 · Settings") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Content Identifier")
                    TextField("UUID", text: $model.contentIdentifier)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                    Button {
                        model.regenerateIdentifier()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("生成新 UUID · Generate a new UUID")
                }

                HStack {
                    Text("静态帧时间 Still time")
                    Slider(value: $model.stillImageFraction, in: 0...1)
                        .disabled(model.videoURL == nil)
                    Text(String(format: "%.2f s", model.stillImageTimeSeconds))
                        .font(.body.monospacedDigit())
                        .frame(width: 60, alignment: .trailing)
                }

                HStack {
                    Text("输出目录 Output")
                    Text(model.effectiveOutputDirectory?.path ?? "—")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("选择… Choose…") { model.chooseOutputDirectory() }
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        switch model.runState {
        case .idle:
            Button {
                model.pair()
            } label: {
                Label("配对 Pair", systemImage: "link.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canPair)

        case .running(let progress):
            VStack(spacing: 6) {
                ProgressView(value: progress)
                Text(String(format: "处理中… %.0f%%", progress * 100))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .done(let photo, let video, let validated):
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        validated
                            ? "配对成功，校验通过 · Paired & verified"
                            : "配对成功（校验未通过）· Paired (verification mismatch)",
                        systemImage: validated ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(validated ? .green : .orange)
                    resultRow(url: photo)
                    resultRow(url: video)
                    Button("再次配对 · Pair another") { model.runState = .idle }
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

        case .failed(let message):
            VStack(spacing: 8) {
                Label("失败 · Failed: \(message)", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Button("重试 · Retry") { model.runState = .idle }
            }
        }
    }

    private func resultRow(url: URL) -> some View {
        HStack {
            Image(systemName: url.pathExtension.lowercased() == "mov" ? "video.fill" : "photo.fill")
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("在访达中显示 · Reveal") { model.revealInFinder(url) }
                .controlSize(.small)
        }
    }
}

/// Drop target + preview card for one input file.
private struct InputCard: View {
    let title: String
    let systemImage: String
    let url: URL?
    let info: String
    let existingIdentifier: String?
    let thumbnail: NSImage?
    let onChoose: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                                style: StrokeStyle(lineWidth: 2, dash: url == nil ? [6] : [])
                            )
                    )
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(8)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: systemImage)
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("拖放文件到此处\nDrag & drop here")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: onDrop)

            if let url {
                Text(url.lastPathComponent)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !info.isEmpty {
                    Text(info).font(.caption).foregroundStyle(.secondary)
                }
                if let existingIdentifier {
                    Label(existingIdentifier, systemImage: "checkmark.seal.fill")
                        .font(.caption.monospaced())
                        .foregroundStyle(.green)
                        .help("已存在 Content Identifier · Existing Content Identifier")
                }
            }
            Button("选择文件… Choose…", action: onChoose)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }
}
