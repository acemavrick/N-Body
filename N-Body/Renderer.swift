//
//  Renderer.swift
//  N-Body
//
//  Created by acemavrick on 12/22/25.
//

import MetalKit

class Renderer: NSObject, MTKViewDelegate {
    var device: MTLDevice!
    var cmdQ: MTL4CommandQueue!
    var cmdBuffer: MTL4CommandBuffer!
    var cmdAllocator: MTL4CommandAllocator!
    var argumentTable: MTL4ArgumentTable!
    var residencySet: MTLResidencySet!
    var sharedEvent: MTLSharedEvent!
    var vpSizeBuffer: MTLBuffer!
    var rpState: MTLRenderPipelineState!
    var startTime: CFAbsoluteTime!
    var timeBuffer: MTLBuffer!
    
    init(device mtlDev: MTLDevice) {
        super.init()
        self.device = mtlDev
        
            // Create Metal 4 command queue
        self.cmdQ = self.device.makeMTL4CommandQueue()!
        
        self.cmdBuffer = self.device.makeCommandBuffer()!
        self.cmdAllocator = self.device.makeCommandAllocator()!
        
            // create library and load shader functions
        let library = self.device.makeDefaultLibrary()!
        
        let vertexFuncDesc = MTL4LibraryFunctionDescriptor()
        vertexFuncDesc.library = library
        vertexFuncDesc.name = "vertex_test"
        
        let fragmentFuncDesc = MTL4LibraryFunctionDescriptor()
        fragmentFuncDesc.library = library
        fragmentFuncDesc.name = "fragment_test"
        
        let compilerDescriptor = MTL4CompilerDescriptor()
        let compiler = try! self.device.makeCompiler(descriptor: compilerDescriptor)
        
        let rpDesc = MTL4RenderPipelineDescriptor()
        rpDesc.fragmentFunctionDescriptor = fragmentFuncDesc
        rpDesc.vertexFunctionDescriptor = vertexFuncDesc
        rpDesc.colorAttachments[0].pixelFormat = .bgra8Unorm // i think this is the normal
        
        self.rpState = try! compiler.makeRenderPipelineState(
            descriptor: rpDesc
        )
        
        let argTableDesc = MTL4ArgumentTableDescriptor()
        argTableDesc.maxBufferBindCount = 1
        self.argumentTable = try! device.makeArgumentTable(descriptor: argTableDesc)

        self.startTime = CFAbsoluteTimeGetCurrent()
        self.timeBuffer = device
            .makeBuffer(length: MemoryLayout<Float>.size, options: .storageModeShared)
        
        let residencyDesc = MTLResidencySetDescriptor()
        self.residencySet = try! device.makeResidencySet(descriptor: residencyDesc)
        self.residencySet.addAllocation(timeBuffer)
        self.residencySet.commit()
        self.cmdQ.addResidencySet(self.residencySet)
    }
    
    
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // pass
    }
    
    func draw(in view: MTKView) {
        let elapsed = Float(CFAbsoluteTimeGetCurrent() - startTime)
        timeBuffer.contents().storeBytes(of: elapsed, as: Float.self)
        
        guard let drawable = view.currentDrawable
        else {
            return
        }
        
        var vp = MTLViewport()
        vp.originX = 0
        vp.originY = 0
        vp.width = Double(view.drawableSize.width)
        vp.height = Double(view.drawableSize.height)
        vp.znear = 0
        vp.zfar = 1
        
        self.cmdAllocator.reset()
        self.cmdBuffer.beginCommandBuffer(allocator: self.cmdAllocator)
        
        let configuration: MTL4RenderPassDescriptor = view.currentMTL4RenderPassDescriptor!
        let renderPassEncoder: MTL4RenderCommandEncoder = self.cmdBuffer.makeRenderCommandEncoder(descriptor: configuration)!
        
        renderPassEncoder.setRenderPipelineState(self.rpState)
        renderPassEncoder.setViewport(vp)
        self.argumentTable.setAddress(timeBuffer.gpuAddress, index: 0)
        renderPassEncoder.setArgumentTable(self.argumentTable, stages: .fragment)
        
        renderPassEncoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        
        renderPassEncoder.endEncoding()
        self.cmdBuffer.endCommandBuffer()
        self.cmdQ.waitForDrawable(drawable)
        self.cmdQ.commit([self.cmdBuffer])
        self.cmdQ.signalDrawable(drawable)
        drawable.present()
    }
}
