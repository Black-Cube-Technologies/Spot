import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let vm: LesionViewModel
    @Binding var previewLayer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspect
        // Defer state mutation to avoid the warning
        DispatchQueue.main.async {
            self.previewLayer = v.videoPreviewLayer
            vm.attach(previewLayer: v.videoPreviewLayer)}
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if previewLayer == nil {
            DispatchQueue.main.async { self.previewLayer = uiView.videoPreviewLayer }
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
