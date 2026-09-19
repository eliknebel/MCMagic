//
//  ContentView.swift
//  MCMagic
//
//  Created by Eli Knebel on 9/16/26.
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text("MCMagic")
                        .font(.title2.weight(.semibold))
                    Text("Mission Control for Magic Mouse")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Toggle("Enabled", isOn: $model.isEnabled)
                .toggleStyle(.switch)

            Picker("Swipe to activate", selection: $model.activateSwipeDirection) {
                ForEach(SwipeDirectionPreference.allCases) { direction in
                    Text(direction.title).tag(direction)
                }
            }
            .pickerStyle(.menu)
            .disabled(!model.isEnabled)

            Picker("Swipe to dismiss", selection: $model.dismissSwipeDirection) {
                ForEach(SwipeDirectionPreference.allCases) { direction in
                    Text(direction.title).tag(direction)
                }
            }
            .pickerStyle(.menu)
            .disabled(!model.isEnabled)
        }
        .padding(24)
        .frame(width: 420)
    }
}
