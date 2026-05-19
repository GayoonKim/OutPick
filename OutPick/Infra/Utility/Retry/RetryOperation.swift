//
//  RetryOperation.swift
//  OutPick
//
//  Created by 김가윤 on 1/20/25.
//

import Foundation
import UIKit

func retry<T>(retryCount: Int = 3, delayInSeconds: UInt64 = 2, asyncTask: @escaping () async throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
    
    var remainingAttempts = retryCount
    Task {
        while remainingAttempts > 0 {
            do {
                
                let result = try await asyncTask()
                completion(.success(result))
                return
            } catch {
                
                remainingAttempts -= 1
                if remainingAttempts > 0 {
                    print("재시도... \(retryCount - remainingAttempts)/\(retryCount)")
                    try? await Task.sleep(nanoseconds: delayInSeconds * 1_000_000_000)
                } else {
                    completion(.failure(error))
                    
                    DispatchQueue.main.async {
                        checkNetworkConnection(retryAction: {
                            retry(retryCount: retryCount, delayInSeconds: delayInSeconds, asyncTask: asyncTask, completion: completion)
                        })
                    }
                }
                
            }
        }
    }
    
}

func checkNetworkConnection(retryAction: @escaping () -> Void) {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let rootVC = windowScene.windows.first?.rootViewController else {
        return
    }
    
    let alert = UIAlertController(title: "네트워크 오류", message: "네트워크 연결에 문제가 있어 다시 시작하거나 재시도해야 합니다.", preferredStyle: .alert)
    
    alert.addAction(UIAlertAction(title: "재시도", style: .default, handler: { _ in retryAction() }))
    alert.addAction(UIAlertAction(title: "확인", style: .cancel, handler: nil))
                                  
    rootVC.present(alert, animated: true, completion: nil)
}
