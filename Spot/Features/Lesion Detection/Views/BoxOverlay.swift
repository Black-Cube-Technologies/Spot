//
//  BoxOverlay.swift
//  Spot
//
//  Created by Hasan on 26/08/2025.
//


import SwiftUI

struct BoxOverlay: View {
    let norm: CGRect   // Vision normalized (origin bottom-left)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let rect = CGRect(x: norm.minX * w,
                              y: (1 - norm.maxY) * h,
                              width: norm.width * w,
                              height: norm.height * h)
            Path { $0.addRect(rect) }
                .stroke(.red, lineWidth: 3)
        }
        .allowsHitTesting(false)
    }
}
