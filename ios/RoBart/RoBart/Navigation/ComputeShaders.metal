//
//  ComputeShaders.metal
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/10/24.
//

#include <metal_stdlib>
using namespace metal;

kernel void processVerticesAndUpdateTexture(
    device float3 *vertices [[buffer(0)]],
    texture2d<float, access::read_write> texture [[texture(0)]],
    constant float4x4 &transformMatrix [[buffer(1)]],
    constant uint &textureWidth [[buffer(2)]],
    constant uint &textureHeight [[buffer(3)]],
    uint vid [[thread_position_in_grid]]
) {
    float3 vert = vertices[vid];

    // Transform vertex
    float4 transformedPosition = transformMatrix * float4(vert, 1.0);

    // Calculate texture coordinates
    uint2 texCoord = uint2(
        clamp(uint(transformedPosition.x), 0u, textureWidth - 1),
        clamp(uint(transformedPosition.z), 0u, textureHeight - 1)
    );

    // Read current height
    float currentHeight = texture.read(texCoord).r;

    // Update height if new height is greater
    float newHeight = transformedPosition.y;
    if (newHeight > currentHeight) {
        texture.write(float4(newHeight, 0, 0, 0), texCoord);
    }
}
