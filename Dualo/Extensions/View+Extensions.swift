//
//  View+Extensions.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
