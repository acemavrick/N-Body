//
//  n-body.metal
//  N-Body
//
//  Created by acemavrick on 12/23/25.
//

#include <metal_stdlib>
#include "../Structs.h"

using namespace metal;

struct PointOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float mass;
};

kernel void nbody_compute(
    device const float2* positionsIn [[buffer(0)]],
    device const float2* velocitiesIn [[buffer(1)]],
    device const float* masses [[buffer(2)]],
    device float2* positionsOut [[buffer(3)]],
    device float2* velocitiesOut [[buffer(4)]],
    constant NBodyUniforms& uniforms [[buffer(5)]],
    uint id [[thread_position_in_grid]]
){
    if (id >= uniforms.particleCount) return;
    
    float2 pos = positionsIn[id];
    float2 vel = velocitiesIn[id];
    float2 acc = float2(0.0);
    
    // o(n^2) for now
    for (uint i = 0; i < uniforms.particleCount; i++) {
        if (i == id) continue;
        
        float2 diff = positionsIn[i] - pos;
        float distSq = dot(diff, diff) + uniforms.softening;
        float invDist = rsqrt(distSq);
        float invDistCubed = invDist * invDist * invDist;
        
        acc += diff * (masses[i] * invDistCubed);
    }
    
    acc *= uniforms.G;
    
    vel += acc * uniforms.deltaTime;
    pos += vel * uniforms.deltaTime;
    
    velocitiesOut[id] = vel;
    positionsOut[id] = pos;
}

vertex PointOut nbody_vertex(
    uint vertexID [[vertex_id]],
    device const float* masses [[buffer(2)]],
    device const float2* positions [[buffer(3)]],
    constant CameraUniforms& camera [[buffer(6)]]
){
    PointOut out;
    
    float2 worldPos = positions[vertexID];
    
    float2 scale = camera.zoom * 2.0 / camera.viewportSize;
    float2 clipPos = (worldPos - camera.center) * scale;
    
    out.position = float4(clipPos, 0.0, 1.0);
    out.pointSize = max(2.0, masses[vertexID] * camera.zoom);
    out.mass = masses[vertexID]; // for coloring (maybe)
    
    return out;
}

vertex float4 fade_vertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1, -1),
        float2(3, -1),
        float2(-1, 3)
    };
    return float4(positions[vertexID], 0.0, 1.0);
}

fragment float4 nbody_fragment(
    PointOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
){
    float2 centered = pointCoord - float2(0.5);
    float dist = length(centered) * 2.0;
    float distLessThanOne = 1.0 - step(1.0, dist); // 1.0 if dist < 1.0 else 0.0
    
    float alpha = (1.0 - dist)*distLessThanOne;
    
    return float4(1.0, 0.9, 0.8, alpha) * float4(distLessThanOne);
}

fragment float4 fade_fragment() {
    return float4(0.0, 0.0, 0.0, 0.08);
}

struct CopyOut {
    float4 position [[position]];
    float2 uv;
};

vertex CopyOut copy_vertex(uint vertexID [[vertex_id]]) {
    // full-screen triangle
    float2 positions[3] = {
        float2(-1, -1),
        float2(3, -1),
        float2(-1, 3)
    };
    
    float2 uvs[3] = {
        float2(0, 1),
        float2(2, 1),
        float2(0, -1)
    };
    
    CopyOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

fragment float4 copy_fragment(
    CopyOut in [[stage_in]],
    texture2d<float> srcTexture [[texture(0)]]
) {
    constexpr sampler s(filter::nearest);
    return srcTexture.sample(s, in.uv);
}
