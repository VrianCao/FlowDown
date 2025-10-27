//
//  Created by ktiays on 2025/2/28.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import GlyphixTextFx
import RichEditor
import SnapKit
import UIKit

final class ToolHintView: MessageListRowView {
    enum State {
        case running
        case suceeded
        case failed
    }

    var text: String? {
        didSet { updateContentText() }
    }

    var toolName: String = .init() {
        didSet { updateContentText() }
    }

    var state: State = .running {
        didSet { updateStateImage() }
    }

    var clickHandler: (() -> Void)?

    private let label: UILabel = .init().with {
        $0.font = UIFont.preferredFont(forTextStyle: .body)
        $0.textColor = .label
        $0.minimumScaleFactor = 0.5
        $0.adjustsFontForContentSizeCategory = true
        $0.lineBreakMode = .byTruncatingTail
        $0.numberOfLines = 1
        $0.adjustsFontSizeToFitWidth = true
        $0.textAlignment = .left
    }

    private let symbolView: UIImageView = .init()
    private let decoratedView: UIImageView = .init(image: richEditorIcon(named: "tools"))
    private var isClickable: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        decoratedView.contentMode = .scaleAspectFit
        decoratedView.tintColor = .label

        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        contentView.addSubview(decoratedView)
        contentView.addSubview(symbolView)
        contentView.addSubview(label)

        symbolView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.equalToSuperview().offset(12)
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        contentView.addGestureRecognizer(tapGesture)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let labelSize = label.intrinsicContentSize
        label.frame = .init(
            x: symbolView.frame.maxX + 8,
            y: (contentView.bounds.height - labelSize.height) / 2,
            width: labelSize.width,
            height: labelSize.height
        )

        contentView.frame.size.width = label.frame.maxX + 18
        decoratedView.frame = .init(x: contentView.bounds.width - 12, y: -4, width: 16, height: 16)
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        label.font = theme.fonts.body
    }

    private func updateStateImage() {
        let configuration = UIImage.SymbolConfiguration(scale: .small)
        switch state {
        case .suceeded:
            contentView.backgroundColor = .systemGreen.withAlphaComponent(0.05)
            let image = UIImage(systemName: "checkmark.seal", withConfiguration: configuration)
            symbolView.image = image
            symbolView.tintColor = .systemGreen
        case .running:
            contentView.backgroundColor = .systemBlue.withAlphaComponent(0.05)
            let image = UIImage(systemName: "hourglass", withConfiguration: configuration)
            symbolView.image = image
            symbolView.tintColor = .systemBlue
        default:
            contentView.backgroundColor = .systemRed.withAlphaComponent(0.05)
            let image = UIImage(systemName: "xmark.seal", withConfiguration: configuration)
            symbolView.image = image
            symbolView.tintColor = .systemRed
        }
        postUpdate()
    }

    private func updateContentText() {
        switch state {
        case .running:
            isClickable = false
            label.text = .init(localized: "Tool call for \(toolName) running.")
        case .suceeded:
            isClickable = true
            label.text = .init(localized: "Tool call for \(toolName) completed.")
        case .failed:
            isClickable = true
            label.text = .init(localized: "Tool call for \(toolName) failed.")
        }
        postUpdate()
    }

    func postUpdate() {
        label.invalidateIntrinsicContentSize()
        label.sizeToFit()
        setNeedsLayout()

        withAnimation { self.layoutIfNeeded() }
    }

    @objc
    private func handleTap(_ sender: UITapGestureRecognizer) {
        if isClickable, sender.state == .ended {
            clickHandler?()
        }
    }
}
