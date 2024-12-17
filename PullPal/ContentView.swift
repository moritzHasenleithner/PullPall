//
//  ContentView.swift
//  PullPal
//
//  Created by Moritz Hasenleithner on 17.12.24.
//

import SwiftUI

// SwiftUI Integration
struct CameraViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ViewController {
        return ViewController()
    }
    
    func updateUIViewController(_ uiViewController: ViewController, context: Context) {}
}

// SwiftUI ContentView
struct ContentView: View {
    var body: some View {
        CameraViewControllerWrapper()
            .edgesIgnoringSafeArea(.all)
    }
}
