//
//  BoxDepth.hpp
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

#ifndef BoxDepth_hpp
#define BoxDepth_hpp

#include <CoreVideo/CoreVideo.h>
#include <algorithm>

struct Box2D
{
    int x;
    int y;
    int width;
    int height;

    bool overlaps(const Box2D &other) const
    {
        return !((x >= (other.x + other.width)) ||
                 (y >= (other.y + other.height)) ||
                 (other.x >= (x + width)) ||
                 (other.y >= (y + width)));
    }

    void mergeWith(const Box2D &other)
    {
        int x1 = std::min(x, other.x);
        int y1 = std::min(y, other.y);
        int x2 = std::max(x + width - 1, other.x + other.width - 1);
        int y2 = std::max(y + height - 1 , other.y + other.height - 1);
        int newWidth = x2 - x1 + 1;
        int newHeight = y2 - y1 + 1;
        x = x1;
        y = y1;
        width = newWidth;
        height = newHeight;
    }
};

extern float computeAverageDepthOfBoundingBox(Box2D box, CVPixelBufferRef depthMap, float maximumDepth);

#endif /* BoxDepth_hpp */
