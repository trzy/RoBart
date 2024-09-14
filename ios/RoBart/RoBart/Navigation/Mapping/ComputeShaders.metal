//
//  ComputeShaders.metal
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/10/24.
//

#include <metal_stdlib>
using namespace metal;

kernel void processVerticesAndUpdateOccupancy(
    device float3 *vertices [[buffer(0)]],
    texture2d<float, access::read_write> texture [[texture(0)]],
    constant float4x4 *transformMatrices [[buffer(1)]],
    constant uint *transformIndices [[buffer(2)]],
    constant float3 &centerPosition [[buffer(3)]],
    constant uint &cellsWide [[buffer(4)]],
    constant uint &cellsDeep [[buffer(5)]],
    constant float &cellSide [[buffer(6)]],
    constant float &minOccupiedHeight [[buffer(7)]],
    constant float &maxOccupiedHeight [[buffer(8)]],
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

    // Update occupancy if Y value is within the correct height range
    if (height < minOccupiedHeight || height > maxOccupiedHeight)
    {
        return;
    }

    // Compute center cell of texture
    uint centerCellX = uint(round(cellsWide * 0.5));
    uint centerCellZ = uint(round(cellsDeep * 0.5));
    int2 centerCell = int2(centerCellX, centerCellZ);
    float2 center = float2(centerPosition.x, centerPosition.z);

    // Compute cell that the point lies in
    float2 cellDimensions = float2(cellSide, cellSide);
    int2 coord = int2(floor((point - center) / cellDimensions + 0.5)) + centerCell;
    coord = clamp(coord, int2(0, 0), int2(cellsWide - 1, cellsDeep - 1));
    uint2 texCoord = uint2(coord);

    // Mark cell as occupied. Because of a race condition between the multiple threads accessing
    // this texture, we can only write the same value. Multiple vertices in different threads may
    // map to the same texel. Therefore, we cannot read-modify-write (e.g., to construct a height
    // map).
    texture.write(float4(1.0, 0, 0, 0), texCoord);
}
