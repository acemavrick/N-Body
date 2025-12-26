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
    
    var argumentTable: MTL4ArgumentTable!
    var residencySet: MTLResidencySet!
    
    let maxInFlight = 3
    var sharedEvent: MTLSharedEvent!
    
    // triple buffered
    var cmdBufferArr: [MTL4CommandBuffer] = []
    var cmdAllocatorArr: [MTL4CommandAllocator] = []
    var cameraUniformsBufferArr: [MTLBuffer] = []
    var frameNumber: UInt64 = 0

    var nBodyUniformsBuffer: MTLBuffer!
    var computePipelineState: MTLComputePipelineState!
    var renderPipelineState: MTLRenderPipelineState!

    var positionsBufferA: MTLBuffer!
    var velocitiesBufferA: MTLBuffer!
    var positionsBufferB: MTLBuffer!
    var velocitiesBufferB: MTLBuffer!
    var massesBuffer: MTLBuffer!
    var currentPhysicsBuffer: Int = 0
    var nbUniforms: NBodyUniforms!
    var camUniforms: CameraUniforms!
    
    let particleCount: Int = 40_000
    
    init(device mtlDev: MTLDevice) {
        super.init()
        self.device = mtlDev
        
        let float2Size = MemoryLayout<SIMD2<Float>>.stride
        let floatSize = MemoryLayout<Float>.stride
        
        // make buffers
        self.positionsBufferA = device.makeBuffer(
            length: float2Size * particleCount, options: .storageModeShared)!
        self.positionsBufferB = device.makeBuffer(
            length: float2Size * particleCount, options: .storageModePrivate)!
        self.velocitiesBufferA = device.makeBuffer(
            length: float2Size * particleCount, options: .storageModeShared)!
        self.velocitiesBufferB = device.makeBuffer(
            length: float2Size * particleCount, options: .storageModePrivate)!
        self.massesBuffer = device.makeBuffer(
            length: floatSize * particleCount, options: .storageModeShared)!
        self.nBodyUniformsBuffer = device.makeBuffer(
            length: MemoryLayout<NBodyUniforms>.stride,
            options: .storageModeShared
        )!
        
        // make the triple buffer for camera uniforms
        for _ in 0..<3 {
            self.cameraUniformsBufferArr.append(device.makeBuffer(
                length: MemoryLayout<CameraUniforms>.stride,
                options: .storageModeShared
            )!)
        }
        
        // init the uniforms
        self.camUniforms = CameraUniforms(
            center: SIMD2<Float>(0.0, 0.0),
            viewportSize: SIMD2<Float>(0.0, 0.0),
            zoom: 1.0,
            pad0: 0.0,
            pad1: 0.0,
            pad2: 0.0
        )
        
        self.nbUniforms = NBodyUniforms(
            dt: 1.0/30.0,
            G: 10.0,
            softening: 1.0,
            particleCount: UInt32(self.particleCount)
        )
        
        self.nBodyUniformsBuffer.contents().copyMemory(
            from: &self.nbUniforms, byteCount: MemoryLayout<NBodyUniforms>.stride)
        
            
        self.cmdQ = self.device.makeMTL4CommandQueue()!
        
        makePipelines()

        // make triple cmd buffers
        for _ in 0..<3 {
            self.cmdBufferArr.append(self.device.makeCommandBuffer()!)
            self.cmdAllocatorArr.append(self.device.makeCommandAllocator()!)
        }
        
        // make arg table
        let argTableDesc = MTL4ArgumentTableDescriptor()
        argTableDesc.maxBufferBindCount = 9
        self.argumentTable = try! device.makeArgumentTable(descriptor: argTableDesc)
        
        makeResidencySet()
        
        initParticles()
        
        self.sharedEvent = device.makeSharedEvent()!
    }
    
    // requires: device
    // sets: residency set
    func makeResidencySet() {
        let residencyDesc = MTLResidencySetDescriptor()
        self.residencySet = try! device.makeResidencySet(descriptor: residencyDesc)
        
        self.residencySet.addAllocation(self.positionsBufferA)
        self.residencySet.addAllocation(self.positionsBufferB)
        self.residencySet.addAllocation(self.velocitiesBufferA)
        self.residencySet.addAllocation(self.velocitiesBufferB)
        self.residencySet.addAllocation(self.massesBuffer)
        self.residencySet.addAllocation(self.nBodyUniformsBuffer)
        
        // add triple buffered things
        for i in 0..<3 {
            self.residencySet.addAllocation(self.cameraUniformsBufferArr[i])
        }
        
        self.residencySet.commit()
        self.cmdQ.addResidencySet(self.residencySet)
    }
    
    // requires: device
    // sets: computePipelineState, renderPipelineState
    func makePipelines() {
        // create library, load shader functions, make pipelines
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
        
        self.computePipelineState = try! compiler.makeComputePipelineState(
            descriptor: computeFuncDesc
        )
        
        self.renderPipelineState = try! compiler.makeRenderPipelineState(
            descriptor: rpDesc
        )
    }
    
    // requires: positionsBufferA, velocitiesBufferA, massesBuffer
    // sets: positionsBufferA, velocitiesBufferA, massesBuffer
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
        
        // avg mass since we do random from 1 to 2
        var totalMass: Float = 0.0
        
        var radii: [Float] = []
        var angles: [Float] = []
        
        let maxRadius: Float = 200.0
        
        for i in 0..<self.particleCount {
            // in a disk (for now)
            let angle = Float.random(in: 0..<(2 * .pi))
            let radius = sqrt(Float.random(in: 0..<1)) * maxRadius
            angles.append(angle)
            radii.append(radius)
            
            positions[i] = SIMD2<Float>(cos(angle) * radius, sin(angle) * radius)
            
            masses[i] = Float.random(in: 1.0...2.0)
            totalMass += masses[i]
        }
        
        for i in 0..<self.particleCount {
            let angle = angles[i]
            let radius = radii[i]
            
            let enclosedMassEstimate = (radius * radius) / (maxRadius * maxRadius) * totalMass
            
            let speed: Float = sqrt(nbUniforms.G * enclosedMassEstimate / max(radius, 5.0))
            
            velocities[i] = SIMD2<Float>(-sin(angle) * speed, cos(angle) * speed)
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // pass
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpDesc = view.currentMTL4RenderPassDescriptor
        else {
            return
        }
        
        let bufferIndex = Int(frameNumber % UInt64(maxInFlight))
        
        if (frameNumber >= maxInFlight) {
            sharedEvent.wait(
                untilSignaledValue: frameNumber - UInt64(maxInFlight),
                timeoutMS: 1000
            )
        }
        
        let currAllocator = self.cmdAllocatorArr[bufferIndex]
        let currCmdBuffer = self.cmdBufferArr[bufferIndex]
        let currCamBuffer = self.cameraUniformsBufferArr[bufferIndex]
        
        self.camUniforms.viewportSize = SIMD2<Float>(
            Float(view.drawableSize.width), Float(view.drawableSize.height))
        currCamBuffer.contents().copyMemory(from: &camUniforms,
                                            byteCount: MemoryLayout<CameraUniforms>.stride)
        
        let (posRead, posWrite) = currentPhysicsBuffer == 0
            ? (positionsBufferA!, positionsBufferB!)
            : (positionsBufferB!, positionsBufferA!)
        let (velRead, velWrite) = currentPhysicsBuffer == 0
            ? (velocitiesBufferA!, velocitiesBufferB!)
            : (velocitiesBufferB!, velocitiesBufferA!)

        currAllocator.reset()
        currCmdBuffer.beginCommandBuffer(allocator: currAllocator)
        
        // compute
        let computeEncoder = currCmdBuffer.makeComputeCommandEncoder()!
        computeEncoder.setComputePipelineState(self.computePipelineState)
        
        argumentTable.setAddress(posRead.gpuAddress, index: 0)
        argumentTable.setAddress(velRead.gpuAddress, index: 1)
        argumentTable.setAddress(massesBuffer.gpuAddress, index: 2)
        argumentTable.setAddress(posWrite.gpuAddress, index: 3)
        argumentTable.setAddress(velWrite.gpuAddress, index: 4)
        argumentTable.setAddress(nBodyUniformsBuffer.gpuAddress, index: 5)
        argumentTable.setAddress(currCamBuffer.gpuAddress, index: 6)
        
        computeEncoder.setArgumentTable(self.argumentTable)
        
        let threadsPerGrid = MTLSize(width: particleCount, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: min(256, particleCount), height: 1, depth: 1)
        computeEncoder.dispatchThreads(
            threadsPerGrid: threadsPerGrid,
            threadsPerThreadgroup: threadsPerThreadgroup
        )
        computeEncoder.endEncoding()
        
        // render
        let renderPassEncoder = currCmdBuffer.makeRenderCommandEncoder(descriptor: rpDesc)!
        
        var vp = MTLViewport()
        vp.originX = 0
        vp.originY = 0
        vp.width = Double(view.drawableSize.width)
        vp.height = Double(view.drawableSize.height)
        vp.znear = 0
        vp.zfar = 1
        renderPassEncoder.setViewport(vp)
        
        renderPassEncoder.setArgumentTable(self.argumentTable, stages: .vertex)
        renderPassEncoder.setRenderPipelineState(self.renderPipelineState)

        renderPassEncoder
            .drawPrimitives(primitiveType: .point, vertexStart: 0, vertexCount: particleCount)
        renderPassEncoder.endEncoding()
        
        currCmdBuffer.endCommandBuffer()
        self.cmdQ.waitForDrawable(drawable)
        self.cmdQ.commit([currCmdBuffer])
        self.cmdQ.signalEvent(self.sharedEvent, value: frameNumber)
        self.cmdQ.signalDrawable(drawable)
        
        drawable.present()
        frameNumber += 1
        currentPhysicsBuffer = 1 - currentPhysicsBuffer
    }
}
