//
//  OccupancyMap.hpp
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/8/24.
//

#ifndef OccupancyMap_hpp
#define OccupancyMap_hpp

#include <swift/bridging>

#include <CoreVideo/CoreVideo.h>
#include <simd/simd.h>
#include <memory>
#include <tuple>

class COccupancyMap
{
public:
    COccupancyMap(float width, float depth, float cellWidth, float cellDepth, simd_float3 centerPoint);

    /// Copies the object and uses the same underlying memory as the right-hand side. That is,
    /// modifications to the new occupancy map will also affect the original object.
    COccupancyMap(const COccupancyMap &rhs);

    void clear();

    void updateCellCounts(
        CVPixelBufferRef depthMap,
        simd_float3x3 intrinsics,
        simd_float2 rgbResolution,
        simd_float4x4 viewMatrix,
        float minDepth,
        float maxDepth,
        float minHeight,
        float maxHeight,
        float incomingSampleWeight,
        float previousWeight
    );
    
    void updateOccupancyFromCounts(const COccupancyMap &counts, float thresholdAmount);

    inline std::pair<size_t, size_t> positionToIndices(simd_float3 position) const;

    std::pair<float, float> positionToFractionalIndices(simd_float3 position) const;

    inline float at(size_t cellX, size_t cellZ) const
    {
        return _occupancy[gridIndex(cellX, cellZ)];
    }

    inline float width() const
    {
        return _width;
    }

    inline float depth() const
    {
        return _depth;
    }

    inline float cellWidth() const
    {
        return _cellWidth;
    }

    inline float cellDepth() const
    {
        return _cellDepth;
    }

    inline size_t cellsWide() const
    {
        return _cellsWide;
    }

    inline size_t cellsDeep() const
    {
        return _cellsDeep;
    }

    inline simd_float3 centerPoint() const
    {
        return _centerPoint;
    }

private:
    inline size_t gridIndex(size_t cellX, size_t cellZ) const
    {
        return cellZ * _cellsDeep + cellX;
    }

    inline std::pair<size_t, size_t> centerCell() const;
    inline size_t centerIndex() const;

    float _width;
    float _depth;
    float _cellWidth;
    float _cellDepth;
    size_t _cellsWide;
    size_t _cellsDeep;
    simd_float3 _centerPoint;
    
    std::shared_ptr<float[]> _occupancy;
    std::shared_ptr<simd_float3[]> _worldPosition;
};

#endif /* OccupancyMap_hpp */
