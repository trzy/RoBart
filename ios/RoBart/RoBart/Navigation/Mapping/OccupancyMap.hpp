//
//  OccupancyMap.hpp
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/8/24.
//

#ifndef OccupancyMap_hpp
#define OccupancyMap_hpp

#include <CoreVideo/CoreVideo.h>
#include <simd/simd.h>
#include <algorithm>
#include <memory>

class OccupancyMap
{
public:
    /// Integral X and Z indices into the 2D occupancy map. Used for indexing into the map.
    struct CellIndices
    {
        size_t cellX;
        size_t cellZ;

        CellIndices()
        {
            cellX = 0;
            cellZ = 0;
        }

        CellIndices(size_t cellX, size_t cellZ)
        {
            this->cellX = cellX;
            this->cellZ = cellZ;
        }

        bool operator==(const CellIndices &rhs) const
        {
            return cellX == rhs.cellX && cellZ == rhs.cellZ;
        }

        bool operator!=(const CellIndices &rhs) const
        {
            return cellX != rhs.cellX || cellZ != rhs.cellZ;
        }
    };

    /// Fractional X and Z indices into the 2D occupancy map (not floored to integral values). Useful for visualization, pathing, etc.
    struct FractionalCellIndices
    {
        float cellX;
        float cellZ;

        FractionalCellIndices(float cellX, float cellZ)
        {
            this->cellX = cellX;
            this->cellZ = cellZ;
        }

        bool operator==(const FractionalCellIndices &rhs) const
        {
            return cellX == rhs.cellX && cellZ == rhs.cellZ;
        }
    };

    OccupancyMap(float width, float depth, float cellSide, simd_float3 centerPoint);

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

    void getOccupancyArray(float *occupied, size_t size) const;

    CellIndices positionToCell(simd_float3 position) const;

    FractionalCellIndices positionToFractionalIndices(simd_float3 position) const;

    simd_float3 cellToPosition(CellIndices cell) const
    {
        return _worldPosition[linearIndex(cell)];
    }

    inline float at(CellIndices cell) const
    {
        return _occupancy[linearIndex(cell)];
    }

    inline float at(size_t cellX, size_t cellZ) const
    {
        return _occupancy[linearIndex(cellX, cellZ)];
    }

    inline float width() const
    {
        return _width;
    }

    inline float depth() const
    {
        return _depth;
    }

    inline float cellSide() const
    {
        return _cellSide;
    }

    inline size_t cellsWide() const
    {
        return _cellsWide;
    }

    inline size_t cellsDeep() const
    {
        return _cellsDeep;
    }

    inline size_t numCells() const
    {
        return _cellsWide * _cellsDeep;
    }

    inline simd_float3 centerPoint() const
    {
        return _centerPoint;
    }

    struct CellHash
    {
        std::size_t operator()(const CellIndices &key) const
        {
            static const std::size_t prime1 = 2654435761ULL;
            static const std::size_t prime2 = 2246822519ULL;

            // Hash of first element
            std::size_t hash1 = key.cellX * prime1;

            // Rotate hash1 and XOR with hash of second element
            std::size_t hash2 = (hash1 << 31) | (hash1 >> (sizeof(std::size_t) * 8 - 31));
            hash2 ^= key.cellZ * prime2;

            // Final mix
            return hash1 ^ hash2;
        }
    };

private:
    inline size_t linearIndex(CellIndices cell) const
    {
        return linearIndex(cell.cellX, cell.cellZ);
    }

    inline size_t linearIndex(size_t cellX, size_t cellZ) const
    {
        cellX = std::min(cellX, _cellsWide - 1);
        cellZ = std::min(cellZ, _cellsDeep - 1);
        return cellZ * _cellsDeep + cellX;
    }

    CellIndices centerCell() const;
    size_t centerIndex() const;

    float _width;
    float _depth;
    float _cellSide;
    size_t _cellsWide;
    size_t _cellsDeep;
    simd_float3 _centerPoint;
    
    std::shared_ptr<float[]> _occupancy;
    std::shared_ptr<simd_float3[]> _worldPosition;
};

#endif /* OccupancyMap_hpp */
