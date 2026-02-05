//
//  Mapper.swift
//  OutPick
//
//  Created by 김가윤 on 2/5/26.
//

import Foundation

// 어떤 Domain ↔ DTO 변환이든 이 형태로 통일
protocol Mapper {
    associatedtype DomainModel
    associatedtype DTOModel

    func toDTO(_ domain: DomainModel) -> DTOModel
    func toDomain(_ dto: DTOModel) -> DomainModel
}
