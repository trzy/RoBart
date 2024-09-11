//
//  FindPath.hpp
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/10/24.
//

#ifndef FindPath_hpp
#define FindPath_hpp

#include "OccupancyMap.hpp"
#include <simd/simd.h>
#include <tuple>
#include <vector>

extern std::vector<std::pair<size_t, size_t>> findPath(const OccupancyMap &occupancy, simd_float3 from, simd_float3 to);

#endif /* FindPath_hpp */
