#include <metal_stdlib>
using namespace metal;


// take 4 inputs
// - shape A (front & back)
// - shape B (front & back)
// and perform a boolean Difference operation, returning the results in two textures

// TODO: support more boolean operations

kernel void mergeDepthBuffers(// inputs
                     depth2d<float, access::read> shapeABackTexture [[texture(0)]],
                     depth2d<float, access::read> shapeAFrontTexture [[texture(1)]],
                     depth2d<float, access::read> shapeBBackTexture [[texture(2)]],
                     depth2d<float, access::read> shapeBFrontTexture [[texture(3)]],
                     // outputs
                     texture2d<float, access::write> outBackTexture [[texture(4)]],
                     texture2d<float, access::write> outFrontTexture [[texture(5)]],
                     uint2 gid [[thread_position_in_grid]])
{

  constexpr sampler texSampler(min_filter::linear, mag_filter::linear);

  float black = 0.0f;
  float white = 1.0f;
  float boxBack = shapeABackTexture.read(gid);
  float cylBack = shapeBBackTexture.read(gid);
  
  float boxFront = shapeAFrontTexture.read(gid);
  float cylFront = shapeBFrontTexture.read(gid);
  float maskBack;
  float maskFront;
  float split2;
  float newlyCut;
  
  // Merge Back
  maskBack = (cylBack > boxBack) ? cylBack : white;
  maskFront = (cylBack > boxFront) ? white : cylBack;
  
  split2 = min(maskBack, maskFront);
  newlyCut = (split2 < 1) ? black : maskBack;
  
  outBackTexture.write((newlyCut < 1) ? cylBack : black, gid);
  
  
  // Merge Front
  maskBack = (cylBack <= boxBack) ? white : cylBack;
  maskFront = (cylFront > boxFront) ? white : cylFront;
  
  split2 = max(maskBack, cylFront);
  newlyCut = (split2 < 1) ? max(boxBack, cylFront) : black;
  
  float split = min(maskFront, maskBack);
  float silhouette = (split < 1) ? cylFront : black;
  
  float foo = max(silhouette, newlyCut);
  float finally = min(foo, maskFront);
  outFrontTexture.write(finally, gid);

}