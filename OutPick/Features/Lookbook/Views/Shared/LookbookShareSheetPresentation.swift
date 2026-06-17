//
//  LookbookShareSheetPresentation.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import SwiftUI

extension View {
    @ViewBuilder
    func applyShareSheetPresentation() -> some View {
        if #available(iOS 16.0, *) {
            self
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }

    @ViewBuilder
    func applyShareConfirmationSheetPresentation() -> some View {
        if #available(iOS 16.0, *) {
            self
                .presentationDetents([.height(188)])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}
