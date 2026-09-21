#if DEBUG && targetEnvironment(simulator)
import UIKit

/// Disposable, simulator-only artwork for reviewing layouts without importing
/// anyone's private books. This code and its fixtures are absent from the IPA.
enum AppearancePreviewFixture {
    static let groupID = UUID(uuidString: "A11CE000-0000-4000-8000-000000000201")!

    static func make(in root: URL) throws -> [Book] {
        let titles = ["春日来信", "晴空纪行", "窗边的午后", "月光收藏室", "海风与花", "星夜手记"]
        return try titles.enumerated().map { index, title in
            let id = UUID(uuidString: String(format: "A11CE000-0000-4000-8000-%012d", 301 + index))!
            let relative = id.uuidString.lowercased()
            let pages = root.appendingPathComponent(relative).appendingPathComponent("pages")
            try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
            let landscape = index == 1 || index == 4
            let data = artwork(title: title, index: index, landscape: landscape)
            for page in 1...12 {
                try data.write(to: pages.appendingPathComponent(String(format: "%06d.jpg", page)), options: .atomic)
            }
            return Book(
                id: id,
                title: title,
                kind: .imageCollection,
                sourceFileName: "\(title)（示例）",
                contentRelativePath: "\(relative)/pages",
                coverRelativePath: "\(relative)/pages/000001.jpg",
                coverAspectRatio: landscape ? 1.46 : 0.70,
                pageCount: 12,
                currentPage: index == 0 ? 4 : 0,
                importedAt: Date(timeIntervalSince1970: 1_700_000_000 - Double(index * 60)),
                lastOpenedAt: index == 0 ? .now : nil,
                fileSize: Int64(data.count * 12),
                isFavorite: index.isMultiple(of: 2),
                favoritePages: index == 0 ? [0, 3] : [],
                shelfGroupID: index < 4 ? groupID : nil
            )
        }
    }

    private static func artwork(title: String, index: Int, landscape: Bool) -> Data {
        let size = landscape ? CGSize(width: 1_022, height: 700) : CGSize(width: 560, height: 800)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let hues: [CGFloat] = [0.96, 0.56, 0.36, 0.69, 0.49, 0.76]
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let base = UIColor(hue: hues[index], saturation: 0.20, brightness: 0.94, alpha: 1)
            base.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                UIColor.white.withAlphaComponent(0.48).cgColor,
                UIColor(hue: hues[index], saturation: 0.43, brightness: 0.68, alpha: 1).cgColor
            ] as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            UIColor.white.withAlphaComponent(0.36).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.46, y: size.height * 0.17, width: size.height * 0.37, height: size.height * 0.37))
            let arch = UIBezierPath(roundedRect: CGRect(x: 42, y: 42, width: size.width - 84, height: size.height - 84), cornerRadius: size.width * 0.35)
            UIColor.white.withAlphaComponent(0.5).setStroke()
            arch.lineWidth = 2
            arch.stroke()
            let titleStyle: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            (title as NSString).draw(at: CGPoint(x: 65, y: size.height * 0.65), withAttributes: titleStyle)
            ("二次元小家 · 示例藏书" as NSString).draw(at: CGPoint(x: 68, y: size.height * 0.65 + 72), withAttributes: [
                .font: UIFont.systemFont(ofSize: 19, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8)
            ])
        }
        return image.jpegData(compressionQuality: 0.9)!
    }
}
#endif
