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
    var lastFrameTime: CFAbsoluteTime!
    var frameNumber: UInt64 = 0
    var trailTexture: MTLTexture!
    
    var computePipeline: MTLComputePipelineState!
    var fadePipeline: MTLRenderPipelineState!
    var renderPipelineState: MTLRenderPipelineState!
    var copyPipeline: MTLRenderPipelineState!

    var nBodyUniformsBuffer: MTLBuffer!
    var cameraUniformsBuffer: MTLBuffer!
    var positionsBufferA: MTLBuffer!
    var velocitiesBufferA: MTLBuffer!
    var positionsBufferB: MTLBuffer!
    var velocitiesBufferB: MTLBuffer!
    var massesBuffer: MTLBuffer!
    var currentBuffer: Int = 0
    var camUniforms: CameraUniforms!
    var nbUniforms: NBodyUniforms!
    
    let particleCount: Int = 20_000
    
    init(device mtlDev: MTLDevice) {
        super.init()
        self.device = mtlDev
        
        
        let float2Size = MemoryLayout<SIMD2<Float>>.stride
        let floatSize = MemoryLayout<Float>.stride
        
        // make buffers
        self.positionsBufferA = device.makeBuffer(
            length: float2Size * particleCount, options: .storageModeShared)!
        self.positionsBufferB = device.makeBuffer(
            length: float2Size * particleCount, options: .storageModeShared)!
        self.velocitiesBufferA = device.makeBuffer(
            length: float2Size * particleCount, options: .storageModeShared)!
        self.velocitiesBufferB = device.makeBuffer(
            length: float2Size * particleCount, options: .storageModeShared)!
        self.massesBuffer = device.makeBuffer(
            length: floatSize * particleCount, options: .storageModeShared)!
        self.nBodyUniformsBuffer = device.makeBuffer(
            length: MemoryLayout<NBodyUniforms>.stride,
            options: .storageModeShared
        )!
        self.cameraUniformsBuffer = device.makeBuffer(
            length: MemoryLayout<CameraUniforms>.stride,
            options: .storageModeShared
        )!
        
        self.camUniforms = CameraUniforms(
            center: SIMD2<Float>(0.0, 0.0),
            viewportSize: SIMD2<Float>(0.0, 0.0),
            zoom: 1.0,
            pad0: 0.0,
            pad1: 0.0,
            pad2: 0.0
        )
        self.nbUniforms = NBodyUniforms(
            deltaTime: 0,
            G: 10.0,
            softening: 1.0,
            particleCount: UInt32(self.particleCount)
        )
            
        // create stuff
        self.cmdQ = self.device.makeMTL4CommandQueue()!
        
        self.cmdBuffer = self.device.makeCommandBuffer()!
        self.cmdAllocator = self.device.makeCommandAllocator()!
        
        // create library and load shader functions
        let library = self.device.makeDefaultLibrary()!
        
        let computeFuncDesc = MTL4ComputePipelineDescriptor()
        let computeFunc = MTL4LibraryFunctionDescriptor()
        computeFunc.library = library
        computeFunc.name = "nbody_compute"
        computeFuncDesc.computeFunctionDescriptor = computeFunc
        
        let vertexFuncDesc = MTL4LibraryFunctionDescriptor()
        vertexFuncDesc.library = library
        vertexFuncDesc.name = "nbody_vertex"
        
        let fragmentFuncDesc = MTL4LibraryFunctionDescriptor()
        fragmentFuncDesc.library = library
        fragmentFuncDesc.name = "nbody_fragment"
        
        let fadeVertexDesc = MTL4LibraryFunctionDescriptor()
        fadeVertexDesc.library = library
        fadeVertexDesc.name = "fade_vertex"
        
        let fadeFragmentDesc = MTL4LibraryFunctionDescriptor()
        fadeFragmentDesc.library = library
        fadeFragmentDesc.name = "fade_fragment"
        
        let copyVertDesc = MTL4LibraryFunctionDescriptor()
        copyVertDesc.library = library
        copyVertDesc.name = "copy_vertex"
        
        let copyFragDesc = MTL4LibraryFunctionDescriptor()
        copyFragDesc.library = library
        copyFragDesc.name = "copy_fragment"
        
        let fadeRPDesc = MTL4RenderPipelineDescriptor()
        fadeRPDesc.vertexFunctionDescriptor = fadeVertexDesc
        fadeRPDesc.fragmentFunctionDescriptor = fadeFragmentDesc
        fadeRPDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        fadeRPDesc.colorAttachments[0].blendingState = .enabled
        fadeRPDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        fadeRPDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        fadeRPDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        fadeRPDesc.colorAttachments[0].destinationAlphaBlendFactor = .one

        let compilerDescriptor = MTL4CompilerDescriptor()
        let compiler = try! self.device.makeCompiler(descriptor: compilerDescriptor)
        
        let rpDesc = MTL4RenderPipelineDescriptor()
        rpDesc.fragmentFunctionDescriptor = fragmentFuncDesc
        rpDesc.vertexFunctionDescriptor = vertexFuncDesc
        rpDesc.colorAttachments[0].pixelFormat = .bgra8Unorm // i think this is the normal
        rpDesc.colorAttachments[0].blendingState = .enabled
        rpDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        rpDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        rpDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        rpDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        let copyRPDesc = MTL4RenderPipelineDescriptor()
        copyRPDesc.fragmentFunctionDescriptor = copyFragDesc
        copyRPDesc.vertexFunctionDescriptor = copyVertDesc
        copyRPDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        self.copyPipeline = try! compiler.makeRenderPipelineState(
            descriptor: copyRPDesc
        )
        
        self.computePipeline = try! compiler.makeComputePipelineState(
            descriptor: computeFuncDesc
        )
        
        self.fadePipeline = try! compiler.makeRenderPipelineState(
            descriptor: fadeRPDesc
        )
        
        self.renderPipelineState = try! compiler.makeRenderPipelineState(
            descriptor: rpDesc
        )
        
        let argTableDesc = MTL4ArgumentTableDescriptor()
        argTableDesc.maxBufferBindCount = 8
        argTableDesc.maxTextureBindCount = 1
        self.argumentTable = try! device.makeArgumentTable(descriptor: argTableDesc)
        
        createTrailTexture(size: CGSize(width:1, height:1))
        
        let residencyDesc = MTLResidencySetDescriptor()
        self.residencySet = try! device.makeResidencySet(descriptor: residencyDesc)
        self.residencySet.addAllocation(self.positionsBufferA)
        self.residencySet.addAllocation(self.positionsBufferB)
        self.residencySet.addAllocation(self.velocitiesBufferA)
        self.residencySet.addAllocation(self.velocitiesBufferB)
        self.residencySet.addAllocation(self.massesBuffer)
        self.residencySet.addAllocation(self.nBodyUniformsBuffer)
        self.residencySet.addAllocation(self.cameraUniformsBuffer)
        self.residencySet.addAllocation(self.trailTexture!)
        self.residencySet.commit()
        self.cmdQ.addResidencySet(self.residencySet)
        
        initParticles()
        self.lastFrameTime = CFAbsoluteTimeGetCurrent()
    }
    
    func createTrailTexture(size: CGSize) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        
        self.trailTexture = device.makeTexture(descriptor: descriptor)
    }
    
    func initParticles() {
        let positions = positionsBufferA.contents().bindMemory(
            to: SIMD2<Float>.self,
            capacity: self.particleCount
        )
        let velocities = velocitiesBufferA.contents().bindMemory(
            to: SIMD2<Float>.self,
            capacity: self.particleCount
        )
        let masses = massesBuffer.contents().bindMemory(
            to: Float.self,
            capacity: self.particleCount
        )
        
        for i in 0..<self.particleCount {
            // in a disk (for now)
            let angle = Float.random(in: 0..<(2 * .pi))
            let radius = sqrt(Float.random(in: 0..<1)) * 200
            
            positions[i] = SIMD2<Float>(cos(angle) * radius, sin(angle) * radius)
            
            // circular orbit velocity
            let speed: Float = 8.4
            velocities[i] = SIMD2<Float>(-sin(angle) * speed, cos(angle) * speed)
            
            masses[i] = Float.random(in: 1.0...2.0)
        }
    }
    
    func updateUniforms(deltaTime: Float, viewSize: CGSize) {
        self.nbUniforms.deltaTime = deltaTime
        nBodyUniformsBuffer.contents().copyMemory(
            from: &nbUniforms,
            byteCount: MemoryLayout<NBodyUniforms>.stride
        )
        self.camUniforms.viewportSize = SIMD2<Float>(Float(viewSize.width), Float(viewSize.height))
        cameraUniformsBuffer.contents().copyMemory(
            from: &camUniforms,
            byteCount: MemoryLayout<CameraUniforms>.stride
        )
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        createTrailTexture(size: size)
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable
        else {
            return
        }
        
        if  trailTexture == nil ||
            trailTexture!.width != Int(view.drawableSize.width) ||
            trailTexture.height != Int(view.drawableSize.height)
        {
            createTrailTexture(size: view.drawableSize)
        }
        
        // calc detla time
        let now = CFAbsoluteTimeGetCurrent()
        var deltaTime = Float(now - self.lastFrameTime)
        self.lastFrameTime = now
        deltaTime = min(deltaTime, 1.0/30.0) // clamp to prevent weird stuff
        
        updateUniforms(deltaTime: deltaTime, viewSize: view.drawableSize)
        
        let (posRead, posWrite) = currentBuffer == 0
            ? (positionsBufferA!, positionsBufferB!)
            : (positionsBufferB!, positionsBufferA!)
        let (velRead, velWrite) = currentBuffer == 0
            ? (velocitiesBufferA!, velocitiesBufferB!)
            : (velocitiesBufferB!, velocitiesBufferA!)

        self.cmdAllocator.reset()
        self.cmdBuffer.beginCommandBuffer(allocator: self.cmdAllocator)
        
        // compute
        let computeEncoder = self.cmdBuffer.makeComputeCommandEncoder()!
        computeEncoder.setComputePipelineState(self.computePipeline)
        
        argumentTable.setAddress(posRead.gpuAddress, index: 0)
        argumentTable.setAddress(velRead.gpuAddress, index: 1)
        argumentTable.setAddress(massesBuffer.gpuAddress, index: 2)
        argumentTable.setAddress(posWrite.gpuAddress, index: 3)
        argumentTable.setAddress(velWrite.gpuAddress, index: 4)
        argumentTable.setAddress(nBodyUniformsBuffer.gpuAddress, index: 5)
        argumentTable.setAddress(cameraUniformsBuffer.gpuAddress, index: 6)
        computeEncoder.setArgumentTable(self.argumentTable)
        
        let threadsPerGrid = MTLSize(width: particleCount, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: min(256, particleCount), height: 1, depth: 1)
        computeEncoder.dispatchThreads(
            threadsPerGrid: threadsPerGrid,
            threadsPerThreadgroup: threadsPerThreadgroup
        )
        computeEncoder.endEncoding()
        
        // render
        let trailPassDesc = MTL4RenderPassDescriptor()
        trailPassDesc.colorAttachments[0].texture = trailTexture
        trailPassDesc.colorAttachments[0].loadAction = frameNumber == 0 ? .clear : .load
        trailPassDesc.colorAttachments[0].storeAction = .store
        trailPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        let renderPassEncoder = self.cmdBuffer.makeRenderCommandEncoder(descriptor: trailPassDesc)!
        
        var vp = MTLViewport()
        vp.originX = 0
        vp.originY = 0
        vp.width = Double(view.drawableSize.width)
        vp.height = Double(view.drawableSize.height)
        vp.znear = 0
        vp.zfar = 1
        renderPassEncoder.setViewport(vp)
        
        renderPassEncoder.setRenderPipelineState(self.fadePipeline)
        renderPassEncoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)

        renderPassEncoder.setArgumentTable(self.argumentTable, stages: .vertex)
        renderPassEncoder.setRenderPipelineState(self.renderPipelineState)

        renderPassEncoder
            .drawPrimitives(primitiveType: .point, vertexStart: 0, vertexCount: particleCount)
        renderPassEncoder.endEncoding()
        
        let copyPassDesc = view.currentMTL4RenderPassDescriptor!
        copyPassDesc.colorAttachments[0].loadAction = .dontCare
        
        let copyEncoder = cmdBuffer.makeRenderCommandEncoder(descriptor: copyPassDesc)!
        copyEncoder.setRenderPipelineState(self.copyPipeline)
        argumentTable.setTexture(trailTexture.gpuResourceID, index: 0)
        copyEncoder.setArgumentTable(self.argumentTable, stages: .fragment)
        copyEncoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        copyEncoder.endEncoding()
        
        self.cmdBuffer.endCommandBuffer()
        self.cmdQ.waitForDrawable(drawable)
        self.cmdQ.commit([self.cmdBuffer])
        self.cmdQ.signalDrawable(drawable)
        drawable.present()
        
        currentBuffer = 1 - currentBuffer
        frameNumber += 1
    }
}
