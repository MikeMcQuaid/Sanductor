#if os(iOS)
    import SanductorDomain
    import UIKit

    extension MobileTerminal.Coordinator {
        // MARK: Internal

        @objc
        func stopScrolling() {
            scrollDisplayLink?.invalidate()
            scrollDisplayLink = nil
            scrollTimestamp = nil
            scrolling = MobileTerminalScroll()
        }

        @objc
        func scroll(_ gesture: UIPanGestureRecognizer) {
            guard let view else {
                return
            }

            if gesture.state == .began {
                stopScrolling()
            }
            switch gesture.state {
            case .began,
                 .changed,
                 .ended:
                scrollPoint = gesture.location(in: view)
                sendScroll(scrolling.move(lines: gesture.translation(in: view).y / view.font.lineHeight))
                gesture.setTranslation(.zero, in: view)
                if gesture.state == .ended {
                    scrolling.velocity = gesture.velocity(in: view).y / view.font.lineHeight
                    let link = CADisplayLink(target: self, selector: #selector(coast(_:)))
                    scrollDisplayLink = link
                    link.add(to: .main, forMode: .common)
                }

            default:
                stopScrolling()
            }
        }

        // MARK: Private

        private static let maximumFrameInterval = 0.1

        @objc
        private func coast(_ link: CADisplayLink) {
            guard let view, view.window != nil, UIApplication.shared.applicationState == .active else {
                stopScrolling()
                return
            }

            let elapsed = link.targetTimestamp - (scrollTimestamp ?? link.timestamp)
            scrollTimestamp = link.targetTimestamp
            guard elapsed < Self.maximumFrameInterval else {
                stopScrolling()
                return
            }

            sendScroll(scrolling.advance(seconds: elapsed, decelerationRate: view.decelerationRate.rawValue))
            if scrolling.velocity == 0 {
                stopScrolling()
            }
        }

        private func sendScroll(_ lines: Int) {
            guard let view, lines != 0 else {
                return
            }

            let size = view.terminalDimensions
            let fraction = scrollPoint.x / max(1, view.bounds.width)
            let column = min(max(0, Int(fraction * CGFloat(size.cols))), max(0, size.cols - 1))
            let row = min(max(0, Int(scrollPoint.y / view.font.lineHeight)), max(0, size.rows - 1))
            let command = HerdrTerminal.scrollCommand(upwards: lines > 0, lines: abs(lines), column: column, row: row)
            stream?.send(Data((command + "\n").utf8))
        }
    }
#endif
