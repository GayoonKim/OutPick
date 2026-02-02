//
//  FirstProfileViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit

class FirstProfileViewController: UIViewController {
    
    @IBOutlet var genderButtons: [UIButton]!
    @IBOutlet weak var dateOfBirthTextField: UITextField!
    @IBOutlet weak var nextButton: UIButton!
    
    var genderButtonIndex: Int?
    var selectedGender: String?
    
    let datePicker = UIDatePicker()
    
    var savedBirthDate: Date?
    
    var userProfile = UserProfile(email: nil, nickname: nil, gender: nil, birthdate: nil, thumbPath: nil, originalPath: nil, joinedRooms: [])

    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        guard let genderButtons = genderButtons else {return}
        setupGenderButtons(genderButtons)
        setupDateOfBirthTextFied(dateOfBirthTextField)
        
        nextButton.isEnabled = false
        nextButton.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
        nextButton.clipsToBounds = true
        nextButton.layer.cornerRadius = 10
        
        guard let index = genderButtonIndex, let birthDate = savedBirthDate else { return }
        genderButtons[index].isSelected = true
        datePicker.date = birthDate
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        savedBirthDate = datePicker.date
    }
    
    @IBAction func nextBtnTapped(_ sender: UIButton) {
        performSegue(withIdentifier: "ToSecProfile", sender: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "ToSecProfile" {
            if let secVC = segue.destination as? SecondProfileViewController {
                secVC.userProfile = self.userProfile
            }
        }
    }
    
    @IBAction func genderButtonPressed(_ sender: UIButton) {
        if genderButtonIndex != nil {
            if !sender.isSelected {
                
                for index in genderButtons.indices {
                    genderButtons[index].isSelected = false
                }
                sender.isSelected = true
                genderButtonIndex = genderButtons.firstIndex(of: sender)
                
            } else {
                
                sender.isSelected = false
                genderButtonIndex = nil
                
            }
        }else {
            
            sender.isSelected = true
            genderButtonIndex = genderButtons.firstIndex(of: sender)
            
        }
        
        if let genderBtnIndex = genderButtonIndex,
           let gender = genderButtons[genderBtnIndex].titleLabel?.text {
            userProfile.gender = gender
        }
     
        enableNextBtn()
    }
    
    private func setupGenderButtons(_ buttons: [UIButton]) {
        for index in buttons.indices {
            buttons[index].clipsToBounds = true
            buttons[index].layer.cornerRadius = 10
            buttons[index].backgroundColor = UIColor(white: 0.1, alpha: 0.03)
        }
    }
    
    private func setupDateOfBirthTextFied(_ textField: UITextField) {
        // DatePicker 설정
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .wheels
        datePicker.locale = Locale(identifier: "ko-KR")
        datePicker.addTarget(self, action: #selector(dateChanged), for: .valueChanged)
        
        // Date Picker 최대 날짜 설정
        let calendar = Calendar(identifier: .gregorian)
        let currentDate = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: currentDate)
        
        components.year = components.year! - 15
        components.month = 1
        components.day = 1
        let maxDate = calendar.date(from: components)
        datePicker.maximumDate = maxDate
        
        // dateOfBirthTextField 설정
        dateOfBirthTextField.inputView = datePicker
        dateOfBirthTextField.inputAccessoryView = createToolbar()
        dateOfBirthTextField.borderStyle = .roundedRect
        dateOfBirthTextField.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
        dateOfBirthTextField.delegate = self
        addArrow(dateOfBirthTextField)
    }
    
    @objc func dateChanged() {
        dateOfBirthTextField.text = configureDateFormat(datePicker.date)
    }
    
    private func addArrow(_ textField: UITextField) {
        let arrowImageView = UIImageView(image: UIImage(systemName: "chevron.down"))
        arrowImageView.tintColor = .lightGray
        dateOfBirthTextField.rightView = arrowImageView
        dateOfBirthTextField.rightViewMode = .always
        dateOfBirthTextField.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func createToolbar() -> UIToolbar{
        let toolBar = UIToolbar()
        toolBar.sizeToFit()
        
        let doneButton = UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(donePressed))
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        toolBar.setItems([flexibleSpace, doneButton], animated: false)
        
        return toolBar
    }
    
    @objc func donePressed(_ sender: UIBarButtonItem) {
        dateOfBirthTextField.text = configureDateFormat(datePicker.date)
        if let birthdate = dateOfBirthTextField.text { userProfile.birthdate = birthdate }
        enableNextBtn()
        view.endEditing(true)
    }
    
    private func configureDateFormat(_ date: Date) -> String{
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        return dateFormatter.string(from: datePicker.date)
    }
    
    private func enableNextBtn() {
        if genderButtonIndex != nil && dateOfBirthTextField.text != "" {
            nextButton.isEnabled = true
        } else {
            nextButton.isEnabled = false
        }
    }
}
