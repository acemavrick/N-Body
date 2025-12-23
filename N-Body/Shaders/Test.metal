//
//  Test.metal
//  N-Body
//
//  Created by acemavrick on 12/22/25.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vertex_test(uint vertexID [[vertex_id]]) {
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
    
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}
fragment float4 fragment_test(VertexOut in [[stage_in]]) {
    // simple gradient
    return float4(in.uv.x, in.uv.y, 0.5, 1.0);
}



