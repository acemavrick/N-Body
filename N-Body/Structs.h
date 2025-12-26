//
//  Structs.h
//  N-Body
//
//  Created by acemavrick on 12/23/25.
//

#ifndef Structs_h
#define Structs_h

#include <simd/simd.h>

struct NBodyUniforms {
    float dt;
    float G;
    float softening;
    uint32_t particleCount;
};

struct CameraUniforms {
    simd_float2 center;
    simd_float2 viewportSize;
    float zoom;
    float pad0;
    float pad1;
    float pad2;
};

#endif /* Structs_h */
