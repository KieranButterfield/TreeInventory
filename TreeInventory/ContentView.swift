//
//  ContentView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View { RootTabView() }
}

#Preview {
    ContentView()
        .modelContainer(for: [Project.self, TreeRecord.self], inMemory: true)
}
