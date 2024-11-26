//
//  BoxDepth.cpp
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/23/24.
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
