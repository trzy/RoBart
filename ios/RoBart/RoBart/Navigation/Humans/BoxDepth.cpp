//
//  BoxDepth.cpp
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/23/24.
//

#include "BoxDepth.hpp"

float computeAverageDepthOfBoundingBox(Box2D box, CVPixelBufferRef depthMap, float maximumDepth)
{
    assert(CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32);

    // Clip box to frame
    size_t depthWidth = CVPixelBufferGetWidth(depthMap);
    size_t depthHeight = CVPixelBufferGetHeight(depthMap);
    if (box.x >= depthWidth || box.y >= depthHeight || (box.x + box.width) <= 0 || (box.y + box.height) <= 0)
    {
        return -1;
    }
    box.x = std::max(0, box.x);
    box.y = std::max(0, box.y);
    box.width = std::min(int(depthWidth) - box.x, box.width);
    box.height = std::min(int(depthHeight) - box.y, box.height);

    // Get buffer
    CVPixelBufferLockBaseAddress(depthMap, kCVPixelBufferLock_ReadOnly);
    size_t depthStride = CVPixelBufferGetBytesPerRow(depthMap) / sizeof(float);
    const float *depthValues = reinterpret_cast<const float *>(CVPixelBufferGetBaseAddress(depthMap));

    // Average the depth values within the box that are less than the maximum depth
    float cumulativeDepth = 0;
    size_t numPixelsCounted = 0;
    for (int yi = box.y; yi < (box.y + box.height); yi++)
    {
        const float *line = &depthValues[yi * depthStride + box.x];
        for (int xi = box.x; xi < (box.x + box.width); xi++)
        {
            float depth = *line++;
            if (depth <= maximumDepth)
            {
                cumulativeDepth += depth;
                numPixelsCounted += 1;
            }
        }
    }

    CVPixelBufferUnlockBaseAddress(depthMap, kCVPixelBufferLock_ReadOnly);

    if (numPixelsCounted == 0)
    {
        // No valid depth values to sample -> no result
        return -1;
    }

    return float(cumulativeDepth) / float(numPixelsCounted);
}
