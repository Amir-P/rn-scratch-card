import UIKit

@objc(RnScratchCardViewManager)
class RnScratchCardViewManager: RCTViewManager {

  override func view() -> UIView? {
    return ScratchCardView()
  }
}

class ScratchCardView : UIView {

    private struct Segment {
        let start: CGPoint
        let end: CGPoint
    }

    private var startPoint: CGPoint = .zero
    private var segments = [Segment]()
    private var swiped = false

    private var overlayImage: UIImage? = nil
    private var lineWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    // UIView is opaque by default, so draw(_:) has no alpha channel and
    // CGBlendMode.clear writes black. A non-opaque view keeps scratched
    // pixels transparent. Redraw on resize so the foil is not stretched.
    private func configureView() {
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    @objc var image: NSDictionary? = nil {
        didSet {
            if let url = remoteURL(from: image) {
                loadRemoteImage(from: url)
            } else if let localImage = RCTConvert.uiImage(image) {
                overlayImage = localImage
                setNeedsDisplay()
            }
        }
    }

    private static let imageCache = NSCache<NSString, UIImage>()

    private func remoteURL(from image: NSDictionary?) -> URL? {
        guard let uri = image?["uri"] as? String,
              let url = URL(string: uri),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private func loadRemoteImage(from url: URL) {
        let cacheKey = url.absoluteString as NSString
        if let cached = ScratchCardView.imageCache.object(forKey: cacheKey) {
            overlayImage = cached
            setNeedsDisplay()
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .returnCacheDataElseLoad

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let data = data, let image = UIImage(data: data) else { return }
            ScratchCardView.imageCache.setObject(image, forKey: cacheKey)
            DispatchQueue.main.async {
                self?.overlayImage = image
                self?.setNeedsDisplay()
            }
        }.resume()
    }

    @objc var brushWidth: NSNumber? = nil {
        didSet {
            lineWidth = RCTConvert.cgFloat(brushWidth)
            setNeedsDisplay()
        }
    }

    @objc var onScratch: RCTDirectEventBlock? = nil

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        startPoint = touches.first?.location(in: self) ?? .zero
        swiped = false
        notifyScratch(startPoint)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let endPoint = touches.first?.location(in: self) else { return }
        guard bounds.contains(endPoint) else { return }

        swiped = true
        segments.append(Segment(start: startPoint, end: endPoint))

        startPoint = endPoint

        setNeedsDisplay()
        notifyScratch(endPoint)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !swiped {
            segments.append(Segment(start: startPoint, end: startPoint))
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let overlayImage else { return }

        // Paint the full card. `rect` is only the dirty region, and drawing
        // the foil into that rect would stretch it.
        overlayImage.draw(in: bounds)

        context.setBlendMode(.clear)
        context.setLineCap(.round)
        context.setLineWidth(lineWidth)
        for segment in segments {
            context.move(to: segment.start)
            context.addLine(to: segment.end)
            context.strokePath()
        }
    }

    private func notifyScratch(_ point: CGPoint) {
        guard let onScratch = onScratch else { return }
        let dictionary: [NSString: NSNumber] = [
            "x": point.x as NSNumber,
            "y": point.y as NSNumber
        ]
        onScratch(dictionary)
    }
}
