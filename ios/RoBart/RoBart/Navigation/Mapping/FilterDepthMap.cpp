//
//  FilterDepthMap.cpp
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/8/24.
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

#include "FilterDepthMap.hpp"

void filterDepthMap(CVPixelBufferRef depthMap, CVPixelBufferRef confidenceMap, uint8_t minimumConfidence)
{
    OSType depthFormat = CVPixelBufferGetPixelFormatType(depthMap);
    OSType confidenceFormat = CVPixelBufferGetPixelFormatType(confidenceMap);
    size_t depthWidth = CVPixelBufferGetWidth(depthMap);
    size_t depthHeight = CVPixelBufferGetHeight(depthMap);
    size_t confidenceWidth = CVPixelBufferGetWidth(confidenceMap);
    size_t confidenceHeight = CVPixelBufferGetHeight(confidenceMap);

    assert(depthFormat == kCVPixelFormatType_DepthFloat32);
    assert(confidenceFormat == kCVPixelFormatType_OneComponent8);
    assert(depthWidth == confidenceWidth);
    assert(depthHeight == confidenceHeight);

    size_t width = depthWidth;
    size_t height = depthHeight;

    CVPixelBufferLockBaseAddress(depthMap, 0); // read and write
    CVPixelBufferLockBaseAddress(confidenceMap, kCVPixelBufferLock_ReadOnly);

    size_t offsetToNextLineDepthMap = CVPixelBufferGetBytesPerRow(depthMap) / sizeof(float) - width;
    size_t offsetToNextLineConfidenceMap = CVPixelBufferGetBytesPerRow(confidenceMap) - width;

    float *depthValues = reinterpret_cast<float *>(CVPixelBufferGetBaseAddress(depthMap));
    const uint8_t *confidenceValues = reinterpret_cast<const uint8_t *>(CVPixelBufferGetBaseAddress(confidenceMap));
    if (!depthValues || !confidenceValues)
    {
        goto end;
    }

    if (offsetToNextLineDepthMap == 0 && offsetToNextLineConfidenceMap == 0)
    {
        for (size_t i = 0; i < width * height; i++)
        {
            if (*confidenceValues < minimumConfidence)
            {
                *depthValues = 1e6f;
            }
            depthValues++;
            confidenceValues++;
        }
    }
    else
    {
        for (size_t y = 0; y < height; y++)
        {
            for (size_t x = 0; x < width; x++)
            {
                if (*confidenceValues < minimumConfidence)
                {
                    *depthValues = 1e6f;
                }
                depthValues++;
                confidenceValues++;
            }
            depthValues += offsetToNextLineDepthMap;
            confidenceValues += offsetToNextLineConfidenceMap;
        }
    }

end:
    CVPixelBufferUnlockBaseAddress(depthMap, 0);
    CVPixelBufferUnlockBaseAddress(confidenceMap, kCVPixelBufferLock_ReadOnly);
}
