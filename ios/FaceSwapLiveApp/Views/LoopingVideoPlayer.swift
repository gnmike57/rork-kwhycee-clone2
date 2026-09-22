import SwiftUI
import AVKit

struct LoopingVideoPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(url: url)
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        if uiView.url != url {
            uiView.replace(with: url)
        }
    }

    class LoopingPlayerUIView: UIView {
        private(set) var url: URL
        private var playerLayer = AVPlayerLayer()
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        init(url: URL) {
            self.url = url
            super.init(frame: .zero)
            setUpPlayer()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func replace(with newURL: URL) {
            url = newURL
            looper = nil
            player?.removeAllItems()
            player = nil
            playerLayer.player = nil
            setUpPlayer()
        }

        private func setUpPlayer() {
            let item = AVPlayerItem(url: url)
            let queuePlayer = AVQueuePlayer(playerItem: item)
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            player = queuePlayer

            playerLayer.player = queuePlayer
            playerLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(playerLayer)
            queuePlayer.isMuted = true
            queuePlayer.play()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}
