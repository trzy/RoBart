//
//  HumanInstancing.cpp
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

#include "HumanInstancing.hpp"

int findOverlappingBoxIndex(const std::vector<Box2D> &humans, const Box2D &box)
{
    for (size_t i = 0; i < humans.size(); i++)
    {
        if (box.overlaps(humans[i]))
        {
            return int(i);
        }
    }
    return -1;
}

std::vector<Box2D> findHumans(CVPixelBufferRef segmentationMap, uint8_t minimumConfidence)
{
    assert(CVPixelBufferGetPixelFormatType(segmentationMap) == kCVPixelFormatType_OneComponent8);
    int maskWidth = int(CVPixelBufferGetWidth(segmentationMap));
    int maskHeight =  int(CVPixelBufferGetHeight(segmentationMap));
    CVPixelBufferLockBaseAddress(segmentationMap, kCVPixelBufferLock_ReadOnly);
    size_t offsetToNextLine = CVPixelBufferGetBytesPerRow(segmentationMap) - maskWidth;
    const uint8_t *mask = reinterpret_cast<const uint8_t *>(CVPixelBufferGetBaseAddress(segmentationMap));

    std::vector<Box2D> humans;

    int neighborWindowSize = 17;            // odd number, size of window (width and height) around a mask pixel to search for a neighboring rect to merge with
    int offset = neighborWindowSize / 2;    // how many pixels in either direction window extends

    size_t i = 0;
    for (int yi = 0; yi < maskHeight; yi++)
    {
        for (int xi = 0; xi < maskWidth; xi++)
        {
            if (mask[i++] < minimumConfidence)
            {
                continue;
            }

            // We have found a human pixel. Check to see if there are any existing human boxes
            // nearby that it might belong to.
            Box2D neighborhood = {.x = xi - offset, .y = yi - offset, .width = neighborWindowSize, .height = neighborWindowSize};
            int humanIdx = findOverlappingBoxIndex(humans, neighborhood);
            if (humanIdx < 0)
            {
                // New human found, start with a single pixel box
                humans.emplace_back(Box2D{.x = xi, .y = yi, .width = 1, .height = 1});
            }
            else
            {
                // An existing human was found and its bounding box needs to be expanded
                Box2D existingBox = humans[humanIdx];
                int x2 = existingBox.x + existingBox.width - 1;
                int y2 = existingBox.y + existingBox.height - 1;
                x2 = std::max(x2, xi);
                y2 = std::max(y2, yi);
                int width = x2 - existingBox.x + 1;
                int height = y2 - existingBox.y + 1;
                existingBox = Box2D{.x = existingBox.x, .y = existingBox.y, .width = width, .height = height};

                // Move this box to the front of the list by swapping it with first element
                // because it is likely that this box will be tested again next
                humans[humanIdx] = humans[0];
                humans[0] = existingBox;
            }

        }

        i += offsetToNextLine;
    }

    // Merge overlapping boxes
    bool mergedSomething = false;
    do
    {
        mergedSomething = false;
        for (int i = 0; i < humans.size(); i++)
        {
            // Merge current with all subsequent
            for (int j = i + 1; j < humans.size(); j++)
            {
                if (humans[i].overlaps(humans[j]))
                {
                    // Merge and replace the first box. Remove the second.
                    humans[i].mergeWith(humans[j]);
                    humans.erase(humans.begin() + j);
                    j -= 1;
                    mergedSomething = true;
                }
            }
        }
    }
    while (mergedSomething);

    CVPixelBufferUnlockBaseAddress(segmentationMap, kCVPixelBufferLock_ReadOnly);
    return humans;
}
