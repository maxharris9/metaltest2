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

vertex ColorInOut combinerVert(device vertex_t* vertex_array [[ buffer(0) ]],
                         constant CubeMatrices& matrices [[buffer(1)]],
                         uint vid [[vertex_id]])
{
  ColorInOut out;
  
  float4 tempPosition = float4(float3(vertex_array[vid].position), 1.0);
  out.position = matrices.modelview_projection_matrix * tempPosition;
  out.texCoord = vertex_array[vid].texCoords;
  
  return out;
}

fragment float4 toScreenFrag(ColorInOut in [[stage_in]],
                             depth2d<float> sceneDepthBack [[ texture(0) ]],
                             depth2d<float> sceneDepthFront [[ texture(1) ]])
{
  constexpr sampler texSampler(min_filter::linear, mag_filter::linear);
  float4 sceneBack = sceneDepthBack.sample(texSampler, in.texCoord);
  float4 sceneFront = sceneDepthFront.sample(texSampler, in.texCoord);
  float4 finally = min(sceneBack, sceneFront);
  
  return (pow(sceneFront, 90) - 0.1);
}