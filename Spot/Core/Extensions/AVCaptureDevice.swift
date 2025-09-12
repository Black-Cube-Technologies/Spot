//
//  AVCaptureDevice.swift
//  Spot
//
//  Created by Hasan on 08/09/2025.
//

import AVFoundation

extension AVCaptureDevice{
    var isTooCloseToFocus: Bool {
        lensPosition == 0
    }
}
