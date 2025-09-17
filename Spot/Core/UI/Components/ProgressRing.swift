//
//  ProgressRing.swift
//  Spot
//
//  Created by Hasan on 17/09/2025.
//

import SwiftUI

struct ProgressRing: View {
    var progress: Double          // 0...1
    var lineWidth: CGFloat = 6
    
    var body: some View {
        
        Circle()
            .trim(from: 0, to: max(0, min(1, progress)))
            .stroke(Color.red, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90)) // start at 12 o’clock
        
    }
}
