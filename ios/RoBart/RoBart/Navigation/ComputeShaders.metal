//
//  ComputeShaders.metal
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/10/24.
//

#include <metal_stdlib>
using namespace metal;

kernel void processVerticesAndUpdateHeightmap(
    device float3 *vertices [[buffer(0)]],
    texture2d<float, access::read_write> texture [[texture(0)]],
    constant float4x4 *transformMatrices [[buffer(1)]],
    constant uint *transformIndices [[buffer(2)]],
    constant float3 &centerPosition [[buffer(3)]],
    constant uint &cellsWide [[buffer(4)]],
    constant uint &cellsDeep [[buffer(5)]],
    constant float &cellWidth [[buffer(6)]],
    constant float &cellDepth [[buffer(7)]],
    uint vid [[thread_position_in_grid]]
) 
{
    float3 vert = vertices[vid];
    uint idx = transformIndices[vid];
    float4x4 transformMatrix = transformMatrices[idx];

    // Transform vertex to world space
    float4 transformedPosition = transformMatrix * float4(vert, 1.0);

    // Project point onto xz plane and retain height
    float2 point = float2(transformedPosition.x, transformedPosition.z);
    float height = transformedPosition.y;

    // Compute center cell of texture
    uint centerCellX = uint(round(cellsWide * 0.5));
    uint centerCellZ = uint(round(cellsDeep * 0.5));
    int2 centerCell = int2(centerCellX, centerCellZ);
    float2 center = float2(centerPosition.x, centerPosition.z);

    // Compute cell that the point lies in
    float2 cellDimensions = float2(cellWidth, cellDepth);
    int2 coord = int2(floor((point - center) / cellDimensions + 0.5)) + centerCell;
    coord = clamp(coord, int2(0, 0), int2(cellsWide - 1, cellsDeep - 1));
    uint2 texCoord = uint2(coord);

    // Read current height
    float currentHeight = texture.read(texCoord).r;

    // Update height if new height is greater
    if (height > currentHeight)
    {
        texture.write(float4(height, 0, 0, 0), texCoord);
    }
}
