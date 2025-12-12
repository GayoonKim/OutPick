//
//  CloudFunctionsManager.swift
//  OutPick
//
//  Created by 김가윤 on 12/4/25.
//

import Foundation
import FirebaseFunctions

final class CloudFunctionsManager {
    static let shared = CloudFunctionsManager()

    private lazy var functions = Functions.functions()

    private init() {}

    func callHelloUser(name: String, completion: @escaping (Result<String, Error>) -> Void) {
        let data: [String: Any] = ["name": name]

        functions.httpsCallable("helloUser").call(data) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let dict = result?.data as? [String: Any],
               let text = dict["result"] as? String {
                completion(.success(text))
            } else {
                // 응답 포맷이 예상과 다를 경우
                let parseError = NSError(
                    domain: "CloudFunctions",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "응답 파싱 실패"]
                )
                completion(.failure(parseError))
            }
        }
    }
}
