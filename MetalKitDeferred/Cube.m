//
//  Cube.h
//  MetalKitDeferredLighting
//
//  Created by Bogdan Adam on 12/2/15.
//  Copyright © 2015 Bogdan Adam. All rights reserved.
//

#import "Cube.h"
#import "SharedStructures.h"
#import "math.h"

static const float kWidth  = 10.00f;
static const float kHeight = 10.00f;
static const float kDepth  = -10.00f;

static const float kCubeVertexData[] =
{
     kWidth, -kHeight,  kDepth,  0.0, -1.0,  0.0,
    -kWidth, -kHeight,  kDepth,  0.0, -1.0,  0.0,
    -kWidth, -kHeight, -kDepth,  0.0, -1.0,  0.0,
     kWidth, -kHeight, -kDepth,  0.0, -1.0,  0.0,
     kWidth, -kHeight,  kDepth,  0.0, -1.0,  0.0,
    -kWidth, -kHeight, -kDepth,  0.0, -1.0,  0.0,
    
     kWidth,  kHeight,  kDepth,  1.0,  0.0,  0.0,
     kWidth, -kHeight,  kDepth,  1.0,  0.0,  0.0,
     kWidth, -kHeight, -kDepth,  1.0,  0.0,  0.0,
     kWidth,  kHeight, -kDepth,  1.0,  0.0,  0.0,
     kWidth,  kHeight,  kDepth,  1.0,  0.0,  0.0,
     kWidth, -kHeight, -kDepth,  1.0,  0.0,  0.0,
    
    -kWidth,  kHeight,  kDepth,  0.0,  1.0,  0.0,
     kWidth,  kHeight,  kDepth,  0.0,  1.0,  0.0,
     kWidth,  kHeight, -kDepth,  0.0,  1.0,  0.0,
    -kWidth,  kHeight, -kDepth,  0.0,  1.0,  0.0,
    -kWidth,  kHeight,  kDepth,  0.0,  1.0,  0.0,
     kWidth,  kHeight, -kDepth,  0.0,  1.0,  0.0,
    
    -kWidth, -kHeight,  kDepth, -1.0,  0.0,  0.0,
    -kWidth,  kHeight,  kDepth, -1.0,  0.0,  0.0,
    -kWidth,  kHeight, -kDepth, -1.0,  0.0,  0.0,
    -kWidth, -kHeight, -kDepth, -1.0,  0.0,  0.0,
    -kWidth, -kHeight,  kDepth, -1.0,  0.0,  0.0,
    -kWidth,  kHeight, -kDepth, -1.0,  0.0,  0.0,
    
     kWidth,  kHeight,  kDepth,  0.0,  0.0,  1.0,
    -kWidth,  kHeight,  kDepth,  0.0,  0.0,  1.0,
    -kWidth, -kHeight,  kDepth,  0.0,  0.0,  1.0,
    -kWidth, -kHeight,  kDepth,  0.0,  0.0,  1.0,
     kWidth, -kHeight,  kDepth,  0.0,  0.0,  1.0,
     kWidth,  kHeight,  kDepth,  0.0,  0.0,  1.0,
    
     kWidth, -kHeight, -kDepth,  0.0,  0.0, -1.0,
    -kWidth, -kHeight, -kDepth,  0.0,  0.0, -1.0,
    -kWidth,  kHeight, -kDepth,  0.0,  0.0, -1.0,
     kWidth,  kHeight, -kDepth,  0.0,  0.0, -1.0,
     kWidth, -kHeight, -kDepth,  0.0,  0.0, -1.0,
    -kWidth,  kHeight, -kDepth,  0.0,  0.0, -1.0
};

@implementation Cube
{
    id <MTLBuffer> _cubeModelMatrixBuffer;
}

- (id)initWithDevice:(id<MTLDevice>)_device
{
    self = [super init];
    if (self)
    {
        _vertexBuffer = [_device newBufferWithBytes:kCubeVertexData length:sizeof(kCubeVertexData) options:MTLResourceOptionCPUCacheModeDefault];
        _cubeModelMatrixBuffer.label = @"CubeBuffer";

        _cubeModelMatrixBuffer = [_device newBufferWithLength:sizeof(CubeMatrices) options:MTLResourceOptionCPUCacheModeDefault];
        
        _vertexCount = 36;
    }
    return self;
}

- (void)_reshape:(vector_float2)screenSize
{
//    float *pVertices = (float *)[_vertexBuffer contents];
//    
//    vector_float2 m_Scale = screenSize;
//    m_Scale.x = screenSize.x/2.f;
//    m_Scale.y = -screenSize.y/2.f;
//    
//    if(pVertices != NULL)
//    {
//        // First triangle
//        pVertices[0] = -m_Scale.x;
//        pVertices[1] = -m_Scale.y;
//        
//        pVertices[5] =  m_Scale.x;
//        pVertices[6] = -m_Scale.y;
//        
//        pVertices[10] = -m_Scale.x;
//        pVertices[11] =  m_Scale.y;
//        
//        // Second triangle
//        pVertices[15] =  m_Scale.x;
//        pVertices[16] = -m_Scale.y;
//        
//        pVertices[20] = -m_Scale.x;
//        pVertices[21] =  m_Scale.y;
//        
//        pVertices[25] =  m_Scale.x;
//        pVertices[26] =  m_Scale.y;
//        
//    }

    matrix_float4x4 _projection = ortho2d_oc(0, screenSize.x, 0, screenSize.y, -1.0, 1.0);
    
    matrix_float4x4 model_matrix = matrix_from_translation(screenSize.x/2.f, screenSize.y/2.f, 0.0);
    mvpMatrix = matrix_multiply(_projection, model_matrix);
}

- (void)update:(uint8_t)_constantDataBufferIndex
{
    CubeMatrices *matrixState = (CubeMatrices *)[_cubeModelMatrixBuffer contents];
    matrixState->modelview_projection_matrix = mvpMatrix;
}

- (void)render:(id <MTLRenderCommandEncoder>)renderEncoder
{
    if (_vertexCount > 0)
    {
        [renderEncoder pushDebugGroup:NSStringFromClass([self class])];
        [renderEncoder setVertexBuffer:self.vertexBuffer offset:0 atIndex:0 ];
        [renderEncoder setVertexBuffer:_cubeModelMatrixBuffer offset:0 atIndex:1 ];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:_vertexCount];
        [renderEncoder popDebugGroup];
    }
}

- (void)render:(uint8_t)_constantDataBufferIndex encoder:(id <MTLRenderCommandEncoder>)renderEncoder withTextures:(NSArray *)textures
{
    if (_vertexCount > 0)
    {
        [renderEncoder pushDebugGroup:NSStringFromClass([self class])];
        [renderEncoder setVertexBuffer:self.vertexBuffer offset:0 atIndex:0 ];
        [renderEncoder setVertexBuffer:_cubeModelMatrixBuffer offset:0 atIndex:1 ];
        
        [textures enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [renderEncoder setFragmentTexture:obj atIndex:idx];
        }];
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:_vertexCount];
        [renderEncoder popDebugGroup];
    }
}

@end
