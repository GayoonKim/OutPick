//
//  LookbookRootView.swift
//  OutPick
//
//  Created by 김가윤 on 12/9/25.
//

import SwiftUI

struct LookbookRootView: View {
    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                VStack {
                    Text("룩북")
                        .font(.largeTitle.bold())
                        .padding(.bottom, 16)
                    
                    Text("여기에 브랜드 / 시즌 / 룩북 리스트를 SwiftUI로 구성할 예정")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .navigationTitle("룩북")
            }
        } else {
            // Fallback on earlier versions
        }
    }
}

// 미리보기
#Preview {
    LookbookRootView()
}
