//
//  OrthoDepthRenderer.metal
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/6/24.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn
{
    float3 position [[attribute(0)]];
};

struct VertexOut
{
    float4 position [[position]];
    float depth [[user(depth)]];
};

vertex VertexOut vertexShader(
  VertexIn in [[stage_in]],
  constant float4x4 &modelMatrix [[buffer(1)]],
  constant float4x4 &viewMatrix [[buffer(2)]],
  constant float4x4 &projectionMatrix [[buffer(3)]]
)
{
    VertexOut out;
    float4 worldPosition = modelMatrix * float4(in.position, 1.0);
    float4 viewPosition = viewMatrix * worldPosition;
    out.position = projectionMatrix * viewPosition;
 //   out.depth = -viewPosition.z;  // negative because view space is right-handed
    out.depth = out.position.z;
    out.position.z = 0.3;   //TEMP: force within viewport NDC bounds
    return out;
}

fragment float fragmentShader(VertexOut in [[stage_in]])
{
    return in.depth;
}
