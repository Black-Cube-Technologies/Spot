//
//  RootView.swift
//  Spot
//
//  Created by Hasan on 01/09/2025.
//
import SwiftUI

struct RootView: View {
    @StateObject private var router = Router.shared
    
    var body: some View {
        NavigationStack(path: $router.path) {
            LesionView(camera: CameraService(),
                       detector: LesionDetector())
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .lesionResult(let lesion):
                    LesionResultView(lesion: lesion) // your result screen from earlier
                }
            }
        }
    }
}
