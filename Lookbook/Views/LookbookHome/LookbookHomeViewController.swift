//
//  LookbookHomeViewController.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/25.
//

import UIKit

class LookbookHomeViewController: UIViewController {

    private let testLB: UILabel = {
       let lb = UILabel()
        lb.text = "Hello, World!"
        lb.font = .boldSystemFont(ofSize: 15)
        lb.textColor = .black
        lb.textAlignment = .center
        
        return lb
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(testLB)
        testLB.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            testLB.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            testLB.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            testLB.heightAnchor.constraint(equalToConstant: 200),
            testLB.widthAnchor.constraint(equalToConstant: 200)
        ])
        // Do any additional setup after loading the view.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
