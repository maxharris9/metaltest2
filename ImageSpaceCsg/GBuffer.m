//
//  GBuffer.m
//  MetalKitDeferredLighting
//
//  Created by Max Harris on 6/4/16.
//  Copyright © 2016 Max Harris. All rights reserved.
//

#import "GBuffer.h"

@implementation GBuffer
{
    BOOL _depthEnabled;
    id <MTLDepthStencilState> _dState;
    id <MTLDepthStencilState> _dState2;
    vector_float2 screenSize;
    MTLRenderPassDescriptor *_renderPassDesc;
}


- (id)initWithDevice:(id<MTLDevice>)_device screensize:(vector_float2)sc clearDepth:(float)depth depthStateDescriptor:(MTLDepthStencilDescriptor*)depthStateDesc depthStateDescriptor2:(MTLDepthStencilDescriptor*)depthStateDesc2
{
    self = [super init];
    self.clearDepth = depth;
    if (self)
    {
        screenSize = sc;
        _dState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];
        _dState2 = [_device newDepthStencilStateWithDescriptor:depthStateDesc2];
        
        [self buildBufferWithDevice:_device clearDepth:self.clearDepth];
    }
    return self;
}

- (id)initWithDepthEnabled:(BOOL)enabled device:(id<MTLDevice>)_device screensize:(vector_float2)sc compareFunction:(MTLCompareFunction)cf clearDepth:(float)depth
{
    self = [super init];
    self.clearDepth = depth;
    if (self)
    {
        screenSize = sc;
        
        MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
        if (enabled)
        {
            depthStateDesc.depthCompareFunction = cf;
        }
        else
        {
            depthStateDesc.depthCompareFunction = MTLCompareFunctionAlways;
        }
        depthStateDesc.depthWriteEnabled = enabled;
        _dState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];
        
        [self buildBufferWithDevice:_device clearDepth:self.clearDepth];
    }
    return self;
}

- (void)createTextureFor:(MTLRenderPassColorAttachmentDescriptor *)color size:(vector_float2)s withDevice:(id<MTLDevice>)_device  format:(MTLPixelFormat)format
{
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: format
                                                                                 width: s.x
                                                                                height: s.y
                                                                             mipmapped: NO];
    d.sampleCount = 1;
    d.storageMode = MTLStorageModePrivate;
    d.textureType = MTLTextureType2D;
    d.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    
    id<MTLTexture> texture = [_device newTextureWithDescriptor: d];
    
    color.texture = texture;
    color.loadAction = MTLLoadActionClear;
    color.storeAction = MTLStoreActionStore;
}

- (void)buildBufferWithDevice:(id<MTLDevice>)_device clearDepth:(float)depth
{
    
    MTLTextureDescriptor *textureDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: MTLPixelFormatDepth32Float
                                                                                           width: screenSize.x
                                                                                          height: screenSize.y
                                                                                       mipmapped: NO];
    textureDesc.sampleCount = 1;
    textureDesc.storageMode = MTLStorageModePrivate;
    textureDesc.textureType = MTLTextureType2D;
    textureDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    self.depthTexture = [_device newTextureWithDescriptor: textureDesc];
    
    _renderPassDesc = [[MTLRenderPassDescriptor alloc] init];
    
    //albedo
    _renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.f, 0.f, 0.f, 1.f);
    [self createTextureFor:_renderPassDesc.colorAttachments[0]
                      size:screenSize
                withDevice:_device
                    format:MTLPixelFormatRGBA8Unorm];
    
    //normals + linear_depth
    _renderPassDesc.colorAttachments[1].clearColor = MTLClearColorMake(0.f, 0.f, 0.f, 1.f);
    [self createTextureFor:_renderPassDesc.colorAttachments[1]
                      size:screenSize
                withDevice:_device
                    format:MTLPixelFormatRGBA16Float];

    //depth
    _renderPassDesc.depthAttachment.loadAction = MTLLoadActionClear;
    _renderPassDesc.depthAttachment.storeAction = MTLStoreActionStore;
    _renderPassDesc.depthAttachment.texture = self.depthTexture;
    _renderPassDesc.depthAttachment.clearDepth = depth;
    
//    _renderPassDesc.stencilAttachment.clearStencil
//    _renderPassDesc.stencilAttachment.
//
//    [self createTextureFor:_renderPassDesc.depthAttachment
//                      size:screenSize
//                withDevice:_device
//                    format:MTLPixelFormatDepth32Float];
    
    
    
//    MTLTextureDescriptor *textureDescriptor2 = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatStencil8
//                                                                                                  width:screenSize.x
//                                                                                                 height:screenSize.y
//                                                                                              mipmapped:NO];
//
//    textureDescriptor2.textureType =  MTLTextureType2D;
//    id <MTLTexture> stencilTexture = [_device newTextureWithDescriptor: textureDescriptor2];
    
    MTLRenderPassStencilAttachmentDescriptor *stencilAttachment = _renderPassDesc.stencilAttachment;
//    stencilAttachment.texture = stencilTexture;
    stencilAttachment.loadAction = MTLLoadActionClear;
    stencilAttachment.storeAction = MTLStoreActionDontCare;
    stencilAttachment.clearStencil = 0;
}

- (MTLRenderPassDescriptor *)renderPassDescriptor
{
    return _renderPassDesc;
}

- (id <MTLDepthStencilState>) _depthState
{
    return _dState;
}

- (id <MTLDepthStencilState>) _depthState2
{
    return _dState2;
}

- (void)setScreenSize:(vector_float2)sc device:(id<MTLDevice>)_device
{
    screenSize = sc;
    
    _renderPassDesc.colorAttachments[0].texture = nil;
    _renderPassDesc.colorAttachments[1].texture = nil;
    _renderPassDesc.depthAttachment.texture = nil;
    _renderPassDesc = nil;
    
    [self buildBufferWithDevice:_device clearDepth:self.clearDepth];
}

- (void)dealloc
{
    _renderPassDesc.colorAttachments[0].texture = nil;
    _renderPassDesc.colorAttachments[1].texture = nil;
    _renderPassDesc.depthAttachment.texture = nil;
    _dState = nil;
}

@end
