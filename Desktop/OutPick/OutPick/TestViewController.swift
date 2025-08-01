//
//  TestViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/1/25.
//

import UIKit
import GRDB

class TestViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        print(#function)
        
        Task { @MainActor in
            let profiles = try GRDBManager.shared.fetchUserProfiles(inRoom: "ㅎㅇㅎㅇ")
            for profile in profiles {
                print(profile)
            }
        }
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
