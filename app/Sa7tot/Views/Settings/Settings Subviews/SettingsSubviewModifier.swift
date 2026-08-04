//
//  SettingsSubviewModifier.swift
//  sa7tot
//
//  Created by Rafael Soh on 5/11/23.
//

import Foundation
import SwiftUI

struct SettingsSubviewModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .navigationBarTitle("")
            .navigationBarHidden(true)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.AppPageBackground)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}
