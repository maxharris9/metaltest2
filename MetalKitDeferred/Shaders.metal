//
//  Shaders.metal
//  MetalKitDeferred
//
//  Created by Max Harris on 6/4/2016.
//  Copyright (c) 2016 Max Harris. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>
#include "SharedStructures.h"

using namespace metal;

typedef struct
{
    packed_float3 position;
    packed_float2 texCoords;
} vertex_t;

typedef struct {
    float4 position [[position]];
    float2 texCoord [[user(texturecoord)]];
} ColorInOut;

vertex ColorInOut cubeVert(device vertex_t* vertex_array [[ buffer(0) ]],
                           constant CubeMatrices& matrices [[buffer(1)]],
                           uint vid [[vertex_id]])
{
    ColorInOut out;
    
    float4 tempPosition = float4(float3(vertex_array[vid].position), 1.0);
    out.position = matrices.modelview_projection_matrix * tempPosition;
    out.texCoord = vertex_array[vid].texCoords;
    
    return out;
}

fragment float4 cubeFrag(ColorInOut in [[stage_in]],
                         depth2d<float> boxRearDepth [[ texture(0) ]],
                         depth2d<float> cylinderRearDepth [[ texture(1) ]],
                         depth2d<float> boxFrontDepth [[ texture(2) ]],
                         depth2d<float> cylinderFrontDepth [[ texture(3) ]],
                         texture2d<float> cylinderFrontNormals [[ texture(4) ]])
{
    constexpr sampler texSampler(min_filter::linear, mag_filter::linear);

    float4 black = float4(0.0,0.0,0.0,1.0);
    float4 white = float4(1.0,1.0,1.0,1.0);

    float4 boxRear = boxRearDepth.sample(texSampler, in.texCoord);
    float4 cylRear = cylinderRearDepth.sample(texSampler, in.texCoord);

    float4 boxFront = boxFrontDepth.sample(texSampler, in.texCoord);
    float4 cylFront = cylinderFrontDepth.sample(texSampler, in.texCoord);

    float4 maskRear = (cylRear.r <= boxRear.r) ? white : cylRear;
    float4 maskFront = (cylFront.r > boxFront.r) ? white : cylFront;
    float4 split2 = max(maskRear, cylFront);
    float4 newlyCut = (split2.r < 1) ? max(boxRear, cylFront) : black;
    float4 split = min(maskFront, maskRear);
    float4 silhouette = (split.r < 1) ? cylFront : black;
    float4 finally = min(max(silhouette, newlyCut), maskFront);
    
    float4 cylFrontNormals = cylinderFrontNormals.sample(texSampler, in.texCoord);

    return (pow(finally, 90) - 0.6) + cylFrontNormals/9;
}