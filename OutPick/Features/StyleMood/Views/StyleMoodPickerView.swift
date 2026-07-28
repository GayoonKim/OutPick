import UIKit

final class StyleMoodPickerView: UIView {
    var onToggleMood: ((String) -> Void)?

    private var moods: [StyleMood] = []
    private var selectedMoodIDs: Set<String> = []
    private var hasAnimatedInitialContent = false

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.itemSize = CGSize(width: 150, height: 50)

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.dataSource = self
        view.delegate = self
        view.register(
            StyleMoodTextCard.self,
            forCellWithReuseIdentifier: StyleMoodTextCard.reuseIdentifier
        )
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(moods: [StyleMood], selectedMoodIDs: Set<String>) {
        let shouldAnimateInitialContent = hasAnimatedInitialContent == false && moods.isEmpty == false
        self.moods = moods
        self.selectedMoodIDs = selectedMoodIDs
        collectionView.reloadData()
        if shouldAnimateInitialContent {
            hasAnimatedInitialContent = true
            animateInitialContentIfNeeded()
        }
    }

    private func animateInitialContentIfNeeded() {
        guard UIAccessibility.isReduceMotionEnabled == false else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.collectionView.layoutIfNeeded()
            let cells = self.collectionView.visibleCells.sorted {
                guard let lhs = self.collectionView.indexPath(for: $0),
                      let rhs = self.collectionView.indexPath(for: $1) else {
                    return false
                }
                return lhs.item < rhs.item
            }
            for (index, cell) in cells.enumerated() {
                cell.alpha = 0
                cell.transform = CGAffineTransform(translationX: 0, y: 12)
                UIView.animate(
                    withDuration: 0.3,
                    delay: min(Double(index) * 0.025, 0.2),
                    options: [.curveEaseOut]
                ) {
                    cell.alpha = 1
                    cell.transform = .identity
                }
            }
        }
    }
}

extension StyleMoodPickerView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        moods.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: StyleMoodTextCard.reuseIdentifier,
            for: indexPath
        ) as? StyleMoodTextCard else {
            return UICollectionViewCell()
        }
        let mood = moods[indexPath.item]
        cell.configure(
            title: mood.displayName,
            isSelected: selectedMoodIDs.contains(mood.id)
        )
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        (collectionView.cellForItem(at: indexPath) as? StyleMoodTextCard)?
            .animateSelectionFeedback()
        onToggleMood?(moods[indexPath.item].id)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = floor((collectionView.bounds.width - 10) / 2)
        return CGSize(width: max(120, width), height: 50)
    }
}
