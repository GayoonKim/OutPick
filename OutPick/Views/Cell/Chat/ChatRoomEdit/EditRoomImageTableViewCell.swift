//
//  EditRoomImageTableViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 6/25/25.
//

import UIKit

class EditRoomImageTableViewCell: UITableViewCell {
    static let identifier = "EditRoomImageCell"
    
    private let imgView: UIImageView = {
       let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 20
        imageView.image = UIImage(named: "Default_Profile")
        imageView.backgroundColor = .red
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
        selectionStyle = .none
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        contentView.addSubview(imgView)
        
        NSLayoutConstraint.activate([
            imgView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            imgView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            imgView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 110),
            imgView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -110),
            imgView.heightAnchor.constraint(equalToConstant: 200),
        ])
    }
}
