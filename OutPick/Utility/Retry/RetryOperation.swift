//
//  RetryOperation.swift
//  OutPick
//
//  Created by 김가윤 on 1/20/25.
//

import Foundation

func retry<T>(retryCount: Int = 3, delayInSeconds: UInt64 = 2, asyncTask: @escaping () async throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
    
    var remainingAttempts = retryCount
    Task {
        while remainingAttempts > 0 {
            do {
                
                let result = try await asyncTask()
                completion(.success(result))
                
            } catch {
                
                remainingAttempts -= 1
                if remainingAttempts > 0 {
                    print("재시도... \(retryCount - remainingAttempts)/\(retryCount)")
                    try? await Task.sleep(nanoseconds: delayInSeconds * 1_000_000_000)
                } else {
                    completion(.failure(error))
                }
                
            }
        }
    }
    
}
