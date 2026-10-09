# Live Photo Pairer

将任意 HEIC 照片与 MOV 视频配对为一张 Apple Live Photo 的 macOS 应用。
A macOS app that pairs any HEIC photo with any MOV video into an Apple Live Photo.

---

## 中文

### 原理：Apple 如何配对 Live Photo

通过对 iPhone 拍摄的真实 Live Photo（HEIC + MOV 两个文件）进行元数据逆向分析（exiftool），发现配对的核心机制是**共享 Content Identifier**：

| 位置 | 字段 | 示例值 |
|---|---|---|
| HEIC · Apple MakerNote | tag `0x11` (17) `ContentIdentifier` | `B0C8F762-32B9-4024-AA39-B1B94E631148` |
| MOV · `mdta` metadata | `com.apple.quicktime.content.identifier` | **同一个 UUID** |

只要照片和视频带有**完全相同的 UUID**，Photos（照片）应用就会把它们识别为同一张 Live Photo。

MOV 端另外还包含（本应用会一并写入，行为与 iPhone 一致）：

- `com.apple.quicktime.live-photo.auto` = 1
- `com.apple.quicktime.live-photo.vitality-score` / `…-scoring-version`
- `com.apple.quicktime.full-frame-rate-playback-intent` = 1
- 一条 timed metadata track（`mebx` 格式），其中含一个
  `mdta/com.apple.quicktime.still-image-time` 样本（int8 = -1 / 0xFF），
  标记静态照片对应的视频帧（即"主要照片"那一帧）

### 功能

- 拖放或选择任意 HEIC/JPEG 照片 + MOV/MP4 视频
- 自动生成配对 UUID（若照片已含 Content Identifier 则自动沿用）
- 可调节"静态帧时间"（照片在视频中对应的时刻）
- **视频不重编码**：视频/音频轨以 sample buffer 直通方式拷贝，零画质损失
- 照片端保留全部 EXIF / GPS / MakerNote / XMP / ICC 元数据，仅注入配对 UUID
- 配对完成后自动校验两边 UUID 是否一致

### 系统要求

- macOS 26+
- Apple Silicon（仅 arm64，不构建 Universal/Intel）
- Xcode 27+（含 Swift 6.4 工具链）
- 无任何第三方依赖，仅使用系统框架（SwiftUI / AVFoundation / ImageIO / CoreMedia）

### 构建与运行

```sh
make        # 构建 release、组装 .app、ad-hoc 签名
make run    # 构建并启动
make clean  # 清理
```

产物位于 `.build/LivePhotoPairer.app`。使用 ad-hoc 签名（`codesign -s -`），
无需开发者证书与公证；首次打开如被 Gatekeeper 拦截，右键 → 打开即可。

### 验证配对结果

```sh
exiftool -MakerNotes:ContentIdentifier out.HEIC
exiftool -ContentIdentifier -StillImageTime -ee out.mov
```

两边的 UUID 一致即配对成功；导入 Photos 后应显示为一张 Live Photo。

### 致谢 / 参考

配对机制参考了对真实 iPhone Live Photo 样本的 exiftool 分析，以及
[LimitPoint/LivePhoto](https://github.com/LimitPoint/LivePhoto) 等开源实现。

---

## English

### How Apple pairs a Live Photo

Reverse-engineering genuine iPhone Live Photos (one `.HEIC` + one `.mov`) with
exiftool reveals that pairing is based on a **shared Content Identifier**:

| Location | Field | Example |
|---|---|---|
| HEIC · Apple MakerNote | tag `0x11` (17) `ContentIdentifier` | `B0C8F762-32B9-4024-AA39-B1B94E631148` |
| MOV · `mdta` metadata | `com.apple.quicktime.content.identifier` | **the same UUID** |

As long as the photo and the video carry the **exact same UUID**, the Photos app
recognizes them as a single Live Photo.

The MOV additionally carries (all written by this app, matching iPhone behavior):

- `com.apple.quicktime.live-photo.auto` = 1
- `com.apple.quicktime.live-photo.vitality-score` / `…-scoring-version`
- `com.apple.quicktime.full-frame-rate-playback-intent` = 1
- a timed metadata track (`mebx` format) containing one
  `mdta/com.apple.quicktime.still-image-time` sample (int8 = -1 / 0xFF) that
  marks the video frame corresponding to the still photo (the "key photo")

### Features

- Drag & drop or pick any HEIC/JPEG photo + MOV/MP4 video
- Automatic pairing UUID generation (reuses the photo's existing Content
  Identifier when present)
- Adjustable still-image time (the moment the photo maps to in the video)
- **No video re-encoding**: video/audio tracks are copied via sample-buffer
  passthrough — zero quality loss
- All EXIF / GPS / MakerNote / XMP / ICC metadata on the photo is preserved;
  only the pairing UUID is injected
- Post-pair validation that both files share the identifier

### Requirements

- macOS 26+
- Apple Silicon (arm64 only — no Universal/Intel build)
- Xcode 27+ (Swift 6.4 toolchain)
- Zero third-party dependencies — system frameworks only
  (SwiftUI / AVFoundation / ImageIO / CoreMedia)

### Build & run

```sh
make        # release build, assemble .app, ad-hoc codesign
make run    # build and launch
make clean  # remove artifacts
```

Output: `.build/LivePhotoPairer.app`. Signed ad-hoc (`codesign -s -`); no
Developer ID or notarization required. If Gatekeeper blocks the first launch,
right-click → Open.

### Verifying a pair

```sh
exiftool -MakerNotes:ContentIdentifier out.HEIC
exiftool -ContentIdentifier -StillImageTime -ee out.mov
```

Matching UUIDs on both files means the pair is valid; importing both into
Photos should yield a single Live Photo.

### Credits

The pairing mechanism was derived from exiftool analysis of genuine iPhone
Live Photo samples and open-source implementations such as
[LimitPoint/LivePhoto](https://github.com/LimitPoint/LivePhoto).

---

## License

MIT
