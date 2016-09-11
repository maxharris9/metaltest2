//
//  Quad.h
//  MetalKitDeferredLighting
//
//  Created by Max Harris on 6/4/16.
//  Copyright © 2016 Max Harris. All rights reserved.
//

#import <MetalKit/MetalKit.h>

@interface Quad : NSObject
{
  matrix_float4x4 mvpMatrix;
}

- (id)initWithDevice:(id<MTLDevice>)_device;
- (void)render:(uint8_t)_constantDataBufferIndex encoder:(id <MTLRenderCommandEncoder>)renderEncoder withTexture:(id<MTLTexture>)txt;
- (void)render:(uint8_t)_constantDataBufferIndex encoder:(id <MTLRenderCommandEncoder>)renderEncoder withTextures:(NSArray *)textures;
- (void)_reshape:(vector_float2)screenSize;
- (void)update:(uint8_t)_constantDataBufferIndex;

@property (nonatomic, readonly) id<MTLBuffer> vertexBuffer;
@property (nonatomic, assign) NSUInteger vertexCount;

@end
