//
//  OrthoDepthRenderer.metal
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/6/24.
//
//  This file is part of RoBart.
//
//  RoBart is free software: you can redistribute it and/or modify it under the
//  terms of the GNU General Public License as published by the Free Software
//  Foundation, either version 3 of the License, or (at your option) any later
//  version.
//
//  RoBart is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with RoBart. If not, see <http://www.gnu.org/licenses/>.
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
