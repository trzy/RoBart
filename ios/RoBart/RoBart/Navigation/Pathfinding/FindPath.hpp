//
//  FindPath.hpp
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/10/24.
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

#ifndef FindPath_hpp
#define FindPath_hpp

#include "OccupancyMap.hpp"
#include <simd/simd.h>
#include <vector>

extern std::vector<OccupancyMap::CellIndices> findPath(const OccupancyMap &occupancy, simd_float3 from, simd_float3 to, float robotRadius);

#endif /* FindPath_hpp */
