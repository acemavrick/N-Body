//
//  MetalView.swift
//  N-Body
//
//  Created by acemavrick on 12/22/25.
//

import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable {
    let mtlDevice: MTLDevice
    
    init() {
        self.mtlDevice = MTLCreateSystemDefaultDevice()!
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        // pass
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = self.mtlDevice
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColorMake(0, 0.5, 0.1, 1.0)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.enableSetNeedsDisplay = false
        return mtkView
    }
    
    func makeCoordinator() -> Renderer {
        Renderer(device: self.mtlDevice)
    }
}
