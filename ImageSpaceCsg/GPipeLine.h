//
//  GPipeLine.h
//  MetalKitDeferredLighting
//
//  Created by Max Harris on 6/4/16.
//  Copyright © 2016 Max Harris. All rights reserved.
//

#import <MetalKit/MetalKit.h>

@interface GPipeLine : NSObject

- (id)initWithDevice:(id<MTLDevice>)_device library:(id <MTLLibrary>)_library;
- (id <MTLRenderPipelineState>)_pipeline;

@end
