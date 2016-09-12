//
//  GameViewController.m
//  MetalKitDeferred
//
//  Created by Max Harris on 6/4/2016.
//  Copyright (c) 2016 Max Harris. All rights reserved.
//

#import "GameViewController.h"
#import "SharedStructures.h"

#import "GBuffer.h"
#import "GPipeLine.h"

#import "Quad.h"

#import "math.h"
#import "csg.h"

#import "vec.h"
#import "orbit-camera.h"

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
  id <MTLRenderPipelineState> _pipelineStateFront;
  id <MTLRenderPipelineState> _pipelineStateBack;
  id <MTLDepthStencilState> _depthState;

  // uniforms
  matrix_float4x4 _projectionMatrix;
  matrix_float4x4 _viewMatrix;
  uniforms_t _uniform_buffer;
  float _rotation[3];
  
  // meshes
  MTKMesh *_boxMesh;
  MTKMesh *_cylinderMesh;
  MTKMesh *_coneMesh;
  
  GBuffer *_gBufferBoxBack;
  GBuffer *_gBufferBoxFront;
  GBuffer *_gBufferCylinderBack;
  GBuffer *_gBufferCylinderFront;
  GBuffer *_gBufferConeBack;
  GBuffer *_gBufferConeFront;
  
  GPipeLine *_gPipeline;
  Quad *_quad;

  // Merge Compute Shader
  id <MTLTexture> _mergeScratchTextures[6];
  int _scratchTextureIndex;

  id<MTLComputePipelineState> _mergePipeline;
  id<MTLCommandBuffer> _mergeCommandBuffer;
  id<MTLComputeCommandEncoder> _mergeCommandEncoder;

  // basic camera controls
  BOOL _keys[63236];

  struct {
    uint8_t down;
    float x, y;
  } mouse;

}

- (void)viewDidLoad
{
  csgNode *A = new csgNode(LEAF, NULL, NULL);
  A->shape = new shape();
  csgNode *B = new csgNode(LEAF, NULL, NULL);
  B->shape = new shape();
  csgNode *temp0 = new csgNode(ADD, A, B);

  csgNode *C = new csgNode(LEAF, NULL, NULL);
  C->shape = new shape();
  csgNode *X = new csgNode(INTERSECT, temp0, C);

  csgNode *Y = new csgNode(LEAF, NULL, NULL);
  Y->shape = new shape();
  csgNode *Z = new csgNode(LEAF, NULL, NULL);
  Z->shape = new shape();
  csgNode *temp1 = new csgNode(INTERSECT, Y, Z);

  csgNode *root = new csgNode(SUBTRACT, X, temp1);
  
  NSLog(@"Has children: %d", root->hasChildren());

  csgTree *ct = new csgTree(*root);

  ct->rootNode = ct->normalize(ct->rootNode);
  

  [super viewDidLoad];
  
  _constantDataBufferIndex = 0;
  _inflight_semaphore = dispatch_semaphore_create(3);
  
  [self _setupMetal];
  if (_device)
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


  // Setup key handlers
  [NSEvent addLocalMonitorForEventsMatchingMask:NSKeyDownMask handler:^(NSEvent *event) {
    _keys[[[event characters] characterAtIndex:0]] = true;
    return event;
  }];

  [NSEvent addLocalMonitorForEventsMatchingMask:NSKeyUpMask handler:^(NSEvent *event) {
    _keys[[[event characters] characterAtIndex:0]] = false;
    return event;
  }];

  [[_view window] setAcceptsMouseMovedEvents:true];

  [NSEvent addLocalMonitorForEventsMatchingMask:NSRightMouseUp handler:^(NSEvent *event) {
    mouse.down = false;
    return event;
  }];

  [NSEvent addLocalMonitorForEventsMatchingMask:NSRightMouseDown handler:^(NSEvent *event) {
    mouse.down = true;
    NSPoint mouseLoc = [NSEvent mouseLocation]; //get current mouse position
    mouse.x = mouseLoc.x;
    mouse.y = mouseLoc.y;

    return event;
  }];
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

  // Setup the orbit camera
  vec3 eye = vec3_create(0.0f, 0.0f, 2.5);
  vec3 center = vec3f(0.0f);
  vec3 up = vec3_create(0.0, 1.0, 0.0 );

  orbit_camera_init(eye, center, up);
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

- (void)_setupMergeComputeShader
{
  _scratchTextureIndex = 0;
  id<MTLFunction> kernelFunction = [_defaultLibrary newFunctionWithName:@"mergeDepthBuffers"];
  
  NSError *error;
  _mergePipeline = [_device  newComputePipelineStateWithFunction:kernelFunction error:&error];
  
  vector_float2 screenSize = (vector_float2){static_cast<float>(self.view.bounds.size.width * 2), static_cast<float>(self.view.bounds.size.height * 2)};

  MTLTextureDescriptor *scratchTextureDescriptors[6];
  
  for (int i=0; i<6; i++) {
    scratchTextureDescriptors[i] = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR32Float
                                                                            width:(int)screenSize[0]
                                                                           height:(int)screenSize[1]
                                                                        mipmapped:false];
    
    [scratchTextureDescriptors[i] setPixelFormat:MTLPixelFormatR32Float];
    [scratchTextureDescriptors[i] setMipmapLevelCount:1];
    [scratchTextureDescriptors[i] setUsage:MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead];
    
    _mergeScratchTextures[i] = [_device newTextureWithDescriptor:scratchTextureDescriptors[i]];
  }
}

- (void)_loadAssets
{
  vector_float2 screenSize = (vector_float2) {
    static_cast<float>(self.view.bounds.size.width * 2),
    static_cast<float>(self.view.bounds.size.height * 2)
  };

  _gBufferBoxBack = [[GBuffer alloc] initWithDepthEnabled:YES
                                            device:_device
                                        screensize:screenSize
                                   compareFunction:MTLCompareFunctionGreater
                                        clearDepth:0.0f];

  _gBufferBoxFront = [[GBuffer alloc] initWithDepthEnabled:YES
                                                    device:_device
                                                screensize:screenSize
                                           compareFunction:MTLCompareFunctionLess
                                                clearDepth:1.0f];

  _gBufferCylinderBack = [[GBuffer alloc] initWithDepthEnabled:YES
                                                        device:_device
                                                    screensize:screenSize
                                               compareFunction:MTLCompareFunctionGreater
                                                    clearDepth:0.0f];

  _gBufferCylinderFront = [[GBuffer alloc] initWithDepthEnabled:YES
                                                        device:_device
                                                    screensize:screenSize
                                               compareFunction:MTLCompareFunctionLess
                                                    clearDepth:1.0f];

  _gBufferConeBack = [[GBuffer alloc] initWithDepthEnabled:YES
                                                    device:_device
                                                screensize:screenSize
                                           compareFunction:MTLCompareFunctionGreater
                                                clearDepth:0.0f];

  _gBufferConeFront = [[GBuffer alloc] initWithDepthEnabled:YES
                                                     device:_device
                                                 screensize:screenSize
                                            compareFunction:MTLCompareFunctionLess
                                                 clearDepth:1.0f];
  
  _gPipeline = [[GPipeLine alloc] initWithDevice:_device library:_defaultLibrary];
  _quad = [[Quad alloc] initWithDevice:_device];

  NSError *error;
    
  MDLMesh *boxModel = [MDLMesh newBoxWithDimensions:(vector_float3){5,10,4}
                                           segments:(vector_uint3){1,1,1}
                                       geometryType:MDLGeometryTypeTriangles
                                      inwardNormals:NO
                                          allocator:[[MTKMeshBufferAllocator alloc] initWithDevice: _device]];
      
  MDLMesh *cylinderModel = [MDLMesh newCylinderWithHeight:5.5
                                                    radii:(vector_float2){4,4}
                                           radialSegments:50
                                         verticalSegments:1
                                             geometryType:MDLGeometryKindTriangles
                                            inwardNormals:NO
                                                allocator:[[MTKMeshBufferAllocator alloc] initWithDevice: _device]];
  
  
  MDLMesh *coneModel = [MDLMesh newEllipticalConeWithHeight:3.5
                                                      radii:8.0
                                             radialSegments:50
                                           verticalSegments:1
                                               geometryType:MDLGeometryKindTriangles
                                              inwardNormals:NO
                                                  allocator:[[MTKMeshBufferAllocator alloc] initWithDevice: _device]];

  _boxMesh = [[MTKMesh alloc] initWithMesh:boxModel device:_device error:nil];
  _cylinderMesh = [[MTKMesh alloc] initWithMesh:cylinderModel device:_device error:nil];
  _coneMesh = [[MTKMesh alloc] initWithMesh:coneModel device:_device error:nil];
  
  // Allocate one region of memory for the uniform buffer
  _dynamicConstantBuffer = [_device newBufferWithLength:kMaxBytesPerFrame options:0];
  _dynamicConstantBuffer.label = @"UniformBuffer";
  
  // load the fragment and vertex programs into the library
//  id <MTLFunction> fragmentProgramFront = [_defaultLibrary newFunctionWithName:@"combinerFragFront"];
//  id <MTLFunction> fragmentProgramBack = [_defaultLibrary newFunctionWithName:@"combinerFragBack"];
  id <MTLFunction> fragmentProgramToScreen = [_defaultLibrary newFunctionWithName:@"toScreenFrag"];
  id <MTLFunction> vertexProgram = [_defaultLibrary newFunctionWithName:@"combinerVert"];

  // Create a vertex descriptor from the MTKMesh
  MTLVertexDescriptor *vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(_boxMesh.vertexDescriptor);
  vertexDescriptor.layouts[0].stepRate = 1;
  vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
  
  // Create a reusable pipeline state
  MTLRenderPipelineDescriptor *pipelineStateFrontDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
  pipelineStateFrontDescriptor.label = @"FrontPipeline";
  pipelineStateFrontDescriptor.sampleCount = _view.sampleCount;
  pipelineStateFrontDescriptor.vertexFunction = vertexProgram;
  pipelineStateFrontDescriptor.fragmentFunction = fragmentProgramToScreen;
  pipelineStateFrontDescriptor.vertexDescriptor = vertexDescriptor;
  pipelineStateFrontDescriptor.colorAttachments[0].pixelFormat = _view.colorPixelFormat;
  pipelineStateFrontDescriptor.depthAttachmentPixelFormat = _view.depthStencilPixelFormat;
  pipelineStateFrontDescriptor.stencilAttachmentPixelFormat = _view.depthStencilPixelFormat;
  
  error = NULL;
  _pipelineStateFront = [_device newRenderPipelineStateWithDescriptor:pipelineStateFrontDescriptor error:&error];
  if (!_pipelineStateFront) {
    NSLog(@"Failed to created pipeline state, error %@", error);
  }

  MTLTextureDescriptor* textureDesc = [[MTLTextureDescriptor alloc] init];
  textureDesc.textureType = MTLTextureType2D;
  textureDesc.height = self.view.bounds.size.height * 2;
  textureDesc.width = self.view.bounds.size.width * 2;
  textureDesc.pixelFormat = MTLPixelFormatBGRA8Unorm;
  
  [self _setupMergeComputeShader];
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

- (void)_mergeDepthBuffers:(NSArray *)textures
{
  MTLSize threadgroupCounts = MTLSizeMake(8, 8, 1);
  MTLSize threadgroups = MTLSizeMake([_mergeScratchTextures[0] width] / threadgroupCounts.width,
                                     [_mergeScratchTextures[0] height] / threadgroupCounts.height,
                                     1);
  
  _mergeCommandBuffer = [_commandQueue commandBuffer];
  _mergeCommandEncoder = [_mergeCommandBuffer computeCommandEncoder];
  
  [_mergeCommandEncoder setComputePipelineState:_mergePipeline];
  
  // merge inputs
  [_mergeCommandEncoder setTexture:textures[0] atIndex:0];
  [_mergeCommandEncoder setTexture:textures[1] atIndex:1];
  [_mergeCommandEncoder setTexture:textures[2] atIndex:2];
  [_mergeCommandEncoder setTexture:textures[3] atIndex:3];
  
  // merge outputs
  [_mergeCommandEncoder setTexture:textures[4] atIndex:4];
  [_mergeCommandEncoder setTexture:textures[5] atIndex:5];
  
  [_mergeCommandEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroupCounts];
  [_mergeCommandEncoder endEncoding];
  [_mergeCommandBuffer commit];
  [_mergeCommandBuffer waitUntilCompleted];
}

- (void)_renderOnePass:(id <MTLCommandBuffer>)commandBuffer
{
  // Obtain a renderPassDescriptor generated from the view's drawable textures
  MTLRenderPassDescriptor* renderPassDescriptor = _view.currentRenderPassDescriptor;
  
  if (renderPassDescriptor != nil) // If we have a valid drawable, begin the commands to render into it
  {
    // other textures (texture2d<float> cylinderFront [[ texture(0) ]])
    // [_gBufferCylinderFront renderPassDescriptor].colorAttachments[0].texture, // albedo
    // [_gBufferCylinderFront renderPassDescriptor].colorAttachments[1].texture // normals

    [self _mergeDepthBuffers:@[
                                // inputs
                                _gBufferConeBack.depthTexture,
                                _gBufferConeFront.depthTexture,
                                _gBufferBoxBack.depthTexture,
                                _gBufferBoxFront.depthTexture,
                                // outputs
                                _mergeScratchTextures[_scratchTextureIndex],
                                _mergeScratchTextures[_scratchTextureIndex+1]
                              ]
    ];
    
    [self _mergeDepthBuffers:@[
                                // inputs
                                _mergeScratchTextures[_scratchTextureIndex],
                                _mergeScratchTextures[_scratchTextureIndex+1],
                                _gBufferCylinderBack.depthTexture,
                                _gBufferCylinderFront.depthTexture,
                                // outputs
                                _mergeScratchTextures[_scratchTextureIndex+2],
                                _mergeScratchTextures[_scratchTextureIndex+3]
                              ]
    ];
    
    id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = @"FinalRenderEncoder";
    [renderEncoder pushDebugGroup:@"Draw Final Quad"];
    [renderEncoder setRenderPipelineState:_pipelineStateFront];
    [_quad render:_constantDataBufferIndex
          encoder:renderEncoder
     withTextures:@[ // these get fed into Shaders.metal/cubeFrag()
                     _mergeScratchTextures[_scratchTextureIndex+2],
                     _mergeScratchTextures[_scratchTextureIndex+3]
                   ]
    ];
    [renderEncoder popDebugGroup];
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
       renderPassDesc:[_gBufferBoxFront renderPassDescriptor]
    depthStencilState:[_gBufferBoxFront _depthState]
           debugGroup:@"DrawBoxFront"
                 mesh:_boxMesh];
  
  [self renderGBuffer:commandBuffer
       renderPassDesc:[_gBufferCylinderBack renderPassDescriptor]
    depthStencilState:[_gBufferCylinderBack _depthState]
           debugGroup:@"DrawCylinderBack"
                 mesh:_cylinderMesh];
  
  [self renderGBuffer:commandBuffer
       renderPassDesc:[_gBufferCylinderFront renderPassDescriptor]
    depthStencilState:[_gBufferCylinderFront _depthState]
           debugGroup:@"DrawCylinderFront"
                 mesh:_cylinderMesh];

  [self renderGBuffer:commandBuffer
       renderPassDesc:[_gBufferConeBack renderPassDescriptor]
    depthStencilState:[_gBufferConeBack _depthState]
           debugGroup:@"DrawConeBack"
                 mesh:_coneMesh];
  
  [self renderGBuffer:commandBuffer
       renderPassDesc:[_gBufferConeFront renderPassDescriptor]
    depthStencilState:[_gBufferConeFront _depthState]
           debugGroup:@"DrawConeFront"
                 mesh:_coneMesh];

  [self _renderOnePass:commandBuffer];
  
  // schedule a present once the framebuffer is complete using the current drawable
  [commandBuffer presentDrawable:_view.currentDrawable];

  // The render assumes it can now increment the buffer index and that the previous index won't be touched until we cycle back around to the same index
  _constantDataBufferIndex = (_constantDataBufferIndex + 1) % kMaxInflightBuffers;

  // Finalize rendering here & push the command buffer to the GPU
  [commandBuffer commit];
}

- (void)_reshape
{
  vector_float2 screenSize = (vector_float2){static_cast<float>(self.view.bounds.size.width * 2), static_cast<float>(self.view.bounds.size.height * 2)};
  [_gBufferBoxBack setScreenSize:screenSize device:_device];
  [_gBufferBoxFront setScreenSize:screenSize device:_device];
  [_gBufferCylinderBack setScreenSize:screenSize device:_device];
  [_gBufferCylinderFront setScreenSize:screenSize device:_device];
  [_gBufferConeBack setScreenSize:screenSize device:_device];
  [_gBufferConeFront setScreenSize:screenSize device:_device];
  
  [_quad _reshape:screenSize];
  
  // When reshape is called, update the view and projection matricies since this means the view orientation or size changed
  float aspect = fabs(self.view.bounds.size.width / self.view.bounds.size.height);
  _projectionMatrix = matrix_from_perspective_fov_aspectLH(65.0f * (M_PI / 180.0f), aspect, 0.1f, 25.0f);
  
  _viewMatrix = matrix_from_translation(0.0f, -2.f, 14.0f);
}

- (void)_update
{
  [_quad update:_constantDataBufferIndex];

  if (mouse.down) {
    NSPoint mouseLoc = [NSEvent mouseLocation]; //get current mouse position

    vector_float2 screenSize = (vector_float2){static_cast<float>(self.view.bounds.size.width * 2), static_cast<float>(self.view.bounds.size.height * 2)};

    orbit_camera_rotate(0, 0, 5 * (mouse.x - mouseLoc.x) / screenSize[0], 5 * (mouseLoc.y - mouse.y) / screenSize[1]);

    mouse.x = mouseLoc.x;
    mouse.y = mouseLoc.y;
  }

  matrix_float4x4 base_model;
//  = matrix_multiply(
//                                               matrix_from_translation(0.0f, 0.0f, 0.0f),
//                                               matrix_multiply(matrix_from_rotation(_rotation[1], 0.0f, 1.0f, 0.0f), matrix_from_rotation(_rotation[0], 1.0f, 0.0f, 0.0f)));
//  orbit_cameraView
  orbit_camera_view((float *)&base_model);

  matrix_float4x4 modelViewMatrix = matrix_multiply(_viewMatrix, base_model);
  
  // Load constant buffer data into appropriate buffer at current index
  uniforms_t *uniforms = &((uniforms_t *)[_dynamicConstantBuffer contents])[_constantDataBufferIndex];

  uniforms->normal_matrix = modelViewMatrix;
  uniforms->modelview_matrix = modelViewMatrix;
  uniforms->modelview_projection_matrix = matrix_multiply(_projectionMatrix, modelViewMatrix);

  if (_keys[NSRightArrowFunctionKey]) {
    orbit_camera_rotate(0, 0, .1, 0);
  }

  if (_keys[NSLeftArrowFunctionKey]) {
    orbit_camera_rotate(0, 0, -.1, 0);
  }


  if (_keys[NSUpArrowFunctionKey]) {
    orbit_camera_rotate(0, 0, 0, .1);
  }

  if (_keys[NSDownArrowFunctionKey]) {
    orbit_camera_rotate(0, 0, 0, -.1);
  }
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
