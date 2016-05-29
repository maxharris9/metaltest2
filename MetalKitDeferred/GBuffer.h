//
//  GBuffer.h
//  MetalKitDeferredLighting
//
//  Created by Bogdan Adam on 12/1/15.
//  Copyright © 2015 Bogdan Adam. All rights reserved.
//

#import <MetalKit/MetalKit.h>

@interface GBuffer : NSObject

- (id)initWithDepthEnabled:(BOOL)enabled device:(id<MTLDevice>)_device screensize:(vector_float2)sc compareFunction:(MTLCompareFunction)cf clearDepth:(float)depth;
- (MTLRenderPassDescriptor *)renderPassDescriptor;
- (id <MTLDepthStencilState>) _depthState;
- (void)setScreenSize:(vector_float2)sc device:(id<MTLDevice>)_device;


@property (atomic) id<MTLTexture> depthTexture;
@property (atomic) float clearDepth;

@end
