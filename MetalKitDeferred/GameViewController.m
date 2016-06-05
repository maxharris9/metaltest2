//
//  GameViewController.m
//  MetalKitDeferred
//
//  Created by Bogdan Adam on 12/1/15.
//  Copyright (c) 2015 Bogdan Adam. All rights reserved.
//

#import "GameViewController.h"
#import "SharedStructures.h"

#import "GBuffer.h"
#import "GPipeLine.h"

#import "Quad.h"

#import "math.h"

// The max number of command buffers in flight
static const NSUInteger kMaxInflightBuffers = 3;

// Max API memory buffer size.
static const size_t kMaxBytesPerFrame = 1024*1024;

@implementation GameViewController
{
    // view
    MTKView *_view;
    
    // controller
    dispatch_semaphore_t _inflight_semaphore;
    id <MTLBuffer> _dynamicConstantBuffer;
    uint8_t _constantDataBufferIndex;
    
    // renderer
    id <MTLDevice> _device;
    id <MTLCommandQueue> _commandQueue;
    id <MTLLibrary> _defaultLibrary;
    id <MTLRenderPipelineState> _pipelineState;
    id <MTLDepthStencilState> _depthState;
    
    // uniforms
    matrix_float4x4 _projectionMatrix;
    matrix_float4x4 _viewMatrix;
    uniforms_t _uniform_buffer;
    float _rotation;
    
    // meshes
    MTKMesh *_boxMesh;
    MTKMesh *_cylinderMesh;
    
    GBuffer *_gBufferBoxBack;
    GBuffer *_gBufferCylinderBack;
    GBuffer *_gBufferBoxFront;
    GBuffer *_gBufferCylinderFront;
    GPipeLine *_gPipeline;
    Quad *_quad;

    id <MTLTexture> _depthTexture;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _constantDataBufferIndex = 0;
    _inflight_semaphore = dispatch_semaphore_create(3);
    
    [self _setupMetal];
    if(_device)
    {
        [self _setupView];
        [self _loadAssets];
        [self _reshape];
    }
    else // Fallback to a blank NSView, an application could also fallback to OpenGL here.
    {
        NSLog(@"Metal is not supported on this device");
        self.view = [[NSView alloc] initWithFrame:self.view.frame];
    }
}

- (void)_setupView
{
    _view = (MTKView *)self.view;
    _view.delegate = self;
    _view.device = _device;
    _view.clearColor = MTLClearColorMake(0.f, 0.f, 0.f, 1.f);
    
    // Setup the render target, choose values based on your app
    _view.sampleCount = 1;
    _view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
}

- (void)_setupMetal
{
    // Set the view to use the default device
    _device = MTLCreateSystemDefaultDevice();

    // Create a new command queue
    _commandQueue = [_device newCommandQueue];
    
    // Load all the shader files with a metal file extension in the project
    _defaultLibrary = [_device newDefaultLibrary];
}

- (void)_loadAssets
{
    vector_float2 screenSize = (vector_float2){self.view.bounds.size.width * 2, self.view.bounds.size.height * 2};

    _gBufferBoxBack = [[GBuffer alloc] initWithDepthEnabled:YES
                                              device:_device
                                          screensize:screenSize
                                     compareFunction:MTLCompareFunctionGreater
                                          clearDepth:0.0f];

    _gBufferCylinderBack = [[GBuffer alloc] initWithDepthEnabled:YES
                                               device:_device
                                           screensize:screenSize
                                      compareFunction:MTLCompareFunctionGreater
                                           clearDepth:0.0f];
    
    _gBufferBoxFront = [[GBuffer alloc] initWithDepthEnabled:YES
                                                      device:_device
                                                  screensize:screenSize
                                             compareFunction:MTLCompareFunctionLess
                                                  clearDepth:1.0f];
    
    _gBufferCylinderFront = [[GBuffer alloc] initWithDepthEnabled:YES
                                                          device:_device
                                                      screensize:screenSize
                                                 compareFunction:MTLCompareFunctionLess
                                                      clearDepth:1.0f];

    _gPipeline = [[GPipeLine alloc] initWithDevice:_device library:_defaultLibrary];
    _quad = [[Quad alloc] initWithDevice:_device];

    NSError *error;
    
    MDLMesh *boxModel = [MDLMesh newBoxWithDimensions:(vector_float3){1,10,4}
                                             segments:(vector_uint3){1,1,1}
                                         geometryType:MDLGeometryTypeTriangles
                                        inwardNormals:NO
                                            allocator:[[MTKMeshBufferAllocator alloc] initWithDevice: _device]];
        
    MDLMesh *cylinderModel = [MDLMesh newCylinderWithHeight:0.5
                                                      radii:(vector_float2){4,4}
                                             radialSegments:50
                                           verticalSegments:1
                                               geometryType:MDLGeometryKindTriangles
                                              inwardNormals:NO
                                                  allocator:[[MTKMeshBufferAllocator alloc] initWithDevice: _device]];

    _boxMesh = [[MTKMesh alloc] initWithMesh:boxModel device:_device error:nil];
    _cylinderMesh = [[MTKMesh alloc] initWithMesh:cylinderModel device:_device error:nil];
    
    // Allocate one region of memory for the uniform buffer
    _dynamicConstantBuffer = [_device newBufferWithLength:kMaxBytesPerFrame options:0];
    _dynamicConstantBuffer.label = @"UniformBuffer";
    
    // Load the fragment program into the library
    id <MTLFunction> fragmentProgram = [_defaultLibrary newFunctionWithName:@"cubeFrag"];
    
    // Load the vertex program into the library
    id <MTLFunction> vertexProgram = [_defaultLibrary newFunctionWithName:@"cubeVert"];
    
    // Create a vertex descriptor from the MTKMesh
    MTLVertexDescriptor *vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(_boxMesh.vertexDescriptor);
    vertexDescriptor.layouts[0].stepRate = 1;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    // Create a reusable pipeline state
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.label = @"MyPipeline";
    pipelineStateDescriptor.sampleCount = _view.sampleCount;
    pipelineStateDescriptor.vertexFunction = vertexProgram;
    pipelineStateDescriptor.fragmentFunction = fragmentProgram;
    pipelineStateDescriptor.vertexDescriptor = vertexDescriptor;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = _view.colorPixelFormat;
    pipelineStateDescriptor.depthAttachmentPixelFormat = _view.depthStencilPixelFormat;
    pipelineStateDescriptor.stencilAttachmentPixelFormat = _view.depthStencilPixelFormat;
    
    error = NULL;
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    if (!_pipelineState) {
        NSLog(@"Failed to created pipeline state, error %@", error);
    }
    
    MTLTextureDescriptor* textureDesc = [[MTLTextureDescriptor alloc] init];
    textureDesc.textureType = MTLTextureType2D;
    textureDesc.height = self.view.bounds.size.height * 2;
    textureDesc.width = self.view.bounds.size.width * 2;
    textureDesc.pixelFormat = MTLPixelFormatBGRA8Unorm;

    _depthTexture = [_device newTextureWithDescriptor: textureDesc];
}

- (void)renderGBuffer:(id <MTLCommandBuffer>)commandBuffer renderPassDesc:(MTLRenderPassDescriptor*)renderPassDescriptor depthStencilState:(id <MTLDepthStencilState>)dss debugGroup:(NSString*)dg mesh:(MTKMesh*)mesh {
    if (renderPassDescriptor != nil) {
        id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"gBufferEncoder";
        [renderEncoder setDepthStencilState:dss];
        
        // Set context state
        [renderEncoder pushDebugGroup:dg];
        [renderEncoder setRenderPipelineState:[_gPipeline _pipeline]];
        [renderEncoder setVertexBuffer:mesh.vertexBuffers[0].buffer
                                offset:mesh.vertexBuffers[0].offset
                               atIndex:0];
        
        [renderEncoder setVertexBuffer:_dynamicConstantBuffer
                                offset:(sizeof(uniforms_t) * _constantDataBufferIndex)
                               atIndex:1];
        
        MTKSubmesh* submesh = mesh.submeshes[0];
        
        // Tell the render context we want to draw our primitives
        [renderEncoder drawIndexedPrimitives:submesh.primitiveType
                                  indexCount:submesh.indexCount
                                   indexType:submesh.indexType
                                 indexBuffer:submesh.indexBuffer.buffer
                           indexBufferOffset:submesh.indexBuffer.offset];
        
        [renderEncoder popDebugGroup];
        
        // We're done encoding commands
        [renderEncoder endEncoding];
    }
}

- (void)_render
{
    dispatch_semaphore_wait(_inflight_semaphore, DISPATCH_TIME_FOREVER);
    
    [self _update];

    // Create a new command buffer for each renderpass to the current drawable
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";
    
    // Call the view's completion handler which is required by the view since it will signal its semaphore and set up the next buffer
    __block dispatch_semaphore_t block_sema = _inflight_semaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(block_sema);
    }];

    [self renderGBuffer:commandBuffer
      renderPassDesc:[_gBufferBoxBack renderPassDescriptor]
   depthStencilState:[_gBufferBoxBack _depthState]
          debugGroup:@"DrawBoxBack"
                mesh:_boxMesh];

    [self renderGBuffer:commandBuffer
      renderPassDesc:[_gBufferCylinderBack renderPassDescriptor]
   depthStencilState:[_gBufferCylinderBack _depthState]
          debugGroup:@"DrawCylinderBack"
                mesh:_cylinderMesh];

    [self renderGBuffer:commandBuffer
      renderPassDesc:[_gBufferBoxFront renderPassDescriptor]
   depthStencilState:[_gBufferBoxFront _depthState]
          debugGroup:@"DrawBoxFront"
                mesh:_boxMesh];
    
    [self renderGBuffer:commandBuffer
      renderPassDesc:[_gBufferCylinderFront renderPassDescriptor]
   depthStencilState:[_gBufferCylinderFront _depthState]
          debugGroup:@"DrawCylinderFront"
                mesh:_cylinderMesh];

    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor* renderPassDescriptor = _view.currentRenderPassDescriptor;

    if(renderPassDescriptor != nil) // If we have a valid drawable, begin the commands to render into it
    {
        // Create a render command encoder so we can render into something
        id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"CubeRenderEncoder";

        // Set context state
        [renderEncoder pushDebugGroup:@"DrawCube"];
        [renderEncoder setRenderPipelineState:_pipelineState];

        [_quad render:_constantDataBufferIndex
              encoder:renderEncoder
         withTextures:@[ // these get fed into Shaders.metal/cubeFrag()
                        _gBufferBoxBack.depthTexture,
                        _gBufferCylinderBack.depthTexture,
                        _gBufferBoxFront.depthTexture,
                        _gBufferCylinderFront.depthTexture
                       ]];
        // other textures (texture2d<float> cylinderFront [[ texture(0) ]])
        // [_gBufferCylinderFront renderPassDescriptor].colorAttachments[0].texture, // albedo
        // [_gBufferCylinderFront renderPassDescriptor].colorAttachments[1].texture // normals

        [renderEncoder popDebugGroup];

        // We're done encoding commands
        [renderEncoder endEncoding];
        
        // Schedule a present once the framebuffer is complete using the current drawable
        [commandBuffer presentDrawable:_view.currentDrawable];
    }

    // The render assumes it can now increment the buffer index and that the previous index won't be touched until we cycle back around to the same index
    _constantDataBufferIndex = (_constantDataBufferIndex + 1) % kMaxInflightBuffers;

    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
}

- (void)_reshape
{
    vector_float2 screenSize = (vector_float2){self.view.bounds.size.width * 2, self.view.bounds.size.height * 2};
    [_gBufferBoxBack setScreenSize:screenSize device:_device];
    [_gBufferBoxFront setScreenSize:screenSize device:_device];
    [_gBufferCylinderBack setScreenSize:screenSize device:_device];
    [_gBufferCylinderFront setScreenSize:screenSize device:_device];
    
    [_quad _reshape:screenSize];
    
    // When reshape is called, update the view and projection matricies since this means the view orientation or size changed
    float aspect = fabs(self.view.bounds.size.width / self.view.bounds.size.height);
    _projectionMatrix = matrix_from_perspective_fov_aspectLH(65.0f * (M_PI / 180.0f), aspect, 0.1f, 25.0f);
    
    _viewMatrix = matrix_from_translation(0.0f, -2.f, 14.0f);
}

- (void)_update
{
    [_quad update:_constantDataBufferIndex];
    
    matrix_float4x4 base_model = matrix_multiply(matrix_from_translation(0.0f, 0.0f, 5.0f), matrix_from_rotation(_rotation, 1.0f, 1.0f, 1.0f));
    matrix_float4x4 modelViewMatrix = matrix_multiply(_viewMatrix, base_model);
    
    // Load constant buffer data into appropriate buffer at current index
    uniforms_t *uniforms = &((uniforms_t *)[_dynamicConstantBuffer contents])[_constantDataBufferIndex];

    uniforms->normal_matrix = modelViewMatrix;
    uniforms->modelview_matrix = modelViewMatrix;
    uniforms->modelview_projection_matrix = matrix_multiply(_projectionMatrix, modelViewMatrix);
    
    _rotation += 0.01f;
}

// Called whenever view changes orientation or layout is changed
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    [self _reshape];
}


// Called whenever the view needs to render
- (void)drawInMTKView:(nonnull MTKView *)view
{
    @autoreleasepool {
        [self _render];
    }
}

@end
