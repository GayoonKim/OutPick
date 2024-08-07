//
//  FirstProfileViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit

class FirstProfileViewController: UIViewController {
    
    @IBOutlet var sexButtons: [UIButton]!
    @IBOutlet weak var dateOfBirthTextField: UITextField!
    @IBOutlet weak var nextButton: UIButton!
    
    var sexButtonIndex: Int?
    
    let datePicker = UIDatePicker()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupSexButtons(sexButtons)
        setupDateOfBirthTextFied(dateOfBirthTextField)
        
        nextButton.isEnabled = false
        nextButton.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
    }

    @IBAction func sexButtonPressed(_ sender: UIButton) {
        if sexButtonIndex != nil {
            if !sender.isSelected {
                for index in sexButtons.indices {
                    sexButtons[index].isSelected = false
                }
                sender.isSelected = true
                sexButtonIndex = sexButtons.firstIndex(of: sender)
            } else {
                sender.isSelected = false
                sexButtonIndex = nil
            }
        }else {
            sender.isSelected = true
            sexButtonIndex = sexButtons.firstIndex(of: sender)
        }
     
        enableNextBtn()
    }
    
    private func setupSexButtons(_ buttons: [UIButton]) {
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
        let today = Date()
        var components = DateComponents()
        components.calendar = calendar
        
        components.year = -15
        components.month = -7
        components.day = -5
        let maxDate = calendar.date(byAdding: components, to: today)
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
        enableNextBtn()
        view.endEditing(true)
    }
    
    private func configureDateFormat(_ date: Date) -> String{
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        return dateFormatter.string(from: datePicker.date)
    }
    
    private func enableNextBtn() {
        if sexButtonIndex != nil && dateOfBirthTextField.text != "" {
            nextButton.isEnabled = true
        } else {
            nextButton.isEnabled = false
        }
    }
    
}

extension FirstProfileViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // 키보드로 입력 차단
            return false
        }
}
