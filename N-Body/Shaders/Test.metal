//
//  Test.metal
//  N-Body
//
//  Created by acemavrick on 12/22/25.
//

#include <metal_stdlib>
#define PI 3.1415926536

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

float2 rotate(float2 p, float2 origin, float angle) {
    float2 dp = p - origin;
    float xn = dp.x*cos(angle) - dp.y*sin(angle);
    float yn = dp.x*sin(angle) + dp.y*cos(angle);
    return float2(xn, yn) + origin;
}

float distHelper(float2 in, float2 p) {
    float dist = distance(in, p);
    dist = 1.0 - dist;
    dist = clamp(dist, 0.0, 1.0);
    return dist*dist*dist;
}

fragment float4 fragment_test(VertexOut in [[stage_in]],
                              constant float &time [[buffer(0)]]) {
    // define three points
    float2 red = float2(0.5, 0.0);
    float2 green = float2(0.5, 0.2);
    float2 blue = float2(0.5, 0.4);
    float2 origin = float2(0.5, 0.5);
    
    // move those points based on time
    red = rotate(red, origin, time/2.0);
    green = rotate(green, origin, time);
    blue = rotate(blue, origin, time*2.0);

    float r = distHelper(in.uv,red);
    float g = distHelper(in.uv,green);
    float b = distHelper(in.uv,blue);
    
    return float4(r,g,b,1.0);
}



