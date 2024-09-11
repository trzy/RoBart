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

class OccupancyMap
{
public:
    OccupancyMap(float width, float depth, float cellWidth, float cellDepth, simd_float3 centerPoint);

    /// Copies the object and uses the same underlying memory as the right-hand side. That is,
    /// modifications to the new occupancy map will also affect the original object.
    OccupancyMap(const OccupancyMap &rhs);

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
    
    void updateOccupancyFromCounts(const OccupancyMap &counts, float thresholdAmount);

    void updateOccupancyFromHeightMap(const float *heights, size_t size, float occupancyHeightThreshold);

    void updateOccupancyFromArray(const float *occupied, size_t size);

    std::pair<size_t, size_t> positionToIndices(simd_float3 position) const;

    std::pair<float, float> positionToFractionalIndices(simd_float3 position) const;

    inline float at(size_t cellX, size_t cellZ) const
    {
        return _occupancy[linearIndex(cellX, cellZ)];
    }

    inline float at(std::pair<size_t, size_t> cell) const
    {
        return at(cell.first, cell.second);
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

    struct CellHash
    {
        std::size_t operator()(const std::pair<std::size_t, std::size_t> &key) const
        {
            static const std::size_t prime1 = 2654435761ULL;
            static const std::size_t prime2 = 2246822519ULL;

            // Hash of first element
            std::size_t hash1 = key.first * prime1;

            // Rotate hash1 and XOR with hash of second element
            std::size_t hash2 = (hash1 << 31) | (hash1 >> (sizeof(std::size_t) * 8 - 31));
            hash2 ^= key.second * prime2;

            // Final mix
            return hash1 ^ hash2;
        }
    };

private:
    inline size_t linearIndex(size_t cellX, size_t cellZ) const
    {
        return cellZ * _cellsDeep + cellX;
    }

    std::pair<size_t, size_t> centerCell() const;
    size_t centerIndex() const;

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
