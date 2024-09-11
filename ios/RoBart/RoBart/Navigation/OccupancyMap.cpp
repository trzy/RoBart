//
//  OccupancyMap.cpp
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/8/24.
//

#include "OccupancyMap.hpp"
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <memory>

OccupancyMap::OccupancyMap(float width, float depth, float cellWidth, float cellDepth, simd_float3 centerPoint)
{
    assert(cellWidth <= width);
    assert(cellDepth <= depth);

    _width = width;
    _depth = depth;
    _cellWidth = cellWidth;
    _cellDepth = cellDepth;
    _cellsWide = size_t(floor(width / cellWidth));
    _cellsDeep = size_t(floor(depth / cellDepth));
    _occupancy = std::make_shared<float[]>(_cellsWide * _cellsDeep);
    memset(_occupancy.get(), 0, sizeof(float) * _cellsWide * _cellsDeep);
    _centerPoint = centerPoint;

    // World position at center point of each cell
    _worldPosition = std::make_shared<simd_float3[]>(_cellsWide * _cellsDeep);
    auto center = centerCell();
    float z = centerPoint.z - cellDepth * float(center.second);     // centerPoint.z - cellDepth * center.cellZ
    for (size_t zi = 0; zi < _cellsDeep; zi++)
    {
        float x = centerPoint.x - cellWidth * float(center.first);  // centerPoint.x - cellWidth * center.cellX
        for (size_t xi = 0; xi < _cellsWide; xi++)
        {
            _worldPosition[linearIndex(xi, zi)] = simd_make_float3(x, 0, z);
            x += cellWidth;
        }
        z += cellDepth;
    }
}

OccupancyMap::OccupancyMap(const OccupancyMap &rhs)
    : _width(rhs._width),
      _depth(rhs._depth),
      _cellWidth(rhs._cellWidth),
      _cellDepth(rhs._cellDepth),
      _cellsWide(rhs._cellsWide),
      _cellsDeep(rhs._cellsDeep),
      _centerPoint(rhs._centerPoint),
      _occupancy(rhs._occupancy),
      _worldPosition(rhs._worldPosition)
{
}

std::pair<size_t, size_t> OccupancyMap::centerCell() const
{
    size_t cellX = size_t(round(float(_cellsWide) * 0.5));
    size_t cellZ = size_t(round(float(_cellsDeep) * 0.5));
    return std::make_pair(cellX, cellZ);
}

size_t OccupancyMap::centerIndex() const
{
    auto center = centerCell();
    return linearIndex(center.first, center.second);
}

std::pair<size_t, size_t> OccupancyMap::positionToIndices(simd_float3 position) const
{
    auto center = centerCell();
    size_t centerCellX = center.first;
    size_t centerCellZ = center.second;

    simd_float3 gridCenterPoint = _worldPosition[centerIndex()];

    long xi = long(floor((position.x - gridCenterPoint.x) / _cellWidth + 0.5)) + centerCellX;
    long zi = long(floor((position.z - gridCenterPoint.z) / _cellDepth + 0.5)) + centerCellZ;
    size_t uxi = std::min(size_t(std::max(long(0), xi)), _cellsWide - 1);
    size_t uzi = std::min(size_t(std::max(long(0), zi)), _cellsDeep - 1);

    return std::make_pair(uxi, uzi);
}

std::pair<float, float> OccupancyMap::positionToFractionalIndices(simd_float3 position) const
{
    auto center = centerCell();
    float centerCellX = center.first;
    float centerCellZ = center.second;

    simd_float3 gridCenterPoint = _worldPosition[centerIndex()];

    float xf = ((position.x - gridCenterPoint.x) / _cellWidth) + centerCellX;
    float zf = ((position.z - gridCenterPoint.z) / _cellDepth) + centerCellZ;

    // Clamp to edges. Note that the only difference between this function and positionToIndices()
    // is that the latter adds 0.5 and then floors. Therefore, we know the limits are: [-0.5, s_numCells - 1 + 0.5).
    xf = std::min(std::max(-0.5f, xf), float(_cellsWide - 1) + 0.5f);
    zf = std::min(std::max(-0.5f, zf), float(_cellsDeep - 1) + 0.5f);

    return std::make_pair(xf, zf);
}

void OccupancyMap::updateCellCounts(
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
)
{
    assert(CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32);

    CVPixelBufferLockBaseAddress(depthMap, 0);

    // Get depth intrinsic parameters by scaling by (depthResolution / rgbResolution)
    size_t depthWidth = CVPixelBufferGetWidth(depthMap);
    size_t depthHeight = CVPixelBufferGetHeight(depthMap);
    simd_float2 depthResolution = simd_make_float2(depthWidth, depthHeight);
    simd_float2 scale = depthResolution / rgbResolution;
    simd_float2 invF = (1.0f / scale) * simd_make_float2(1.0f / intrinsics.columns[0].x, 1.0f / intrinsics.columns[1].y);    // 1/(scale_x*fx), 1/(scale_y*fy)
    simd_float2 c = scale * simd_make_float2(intrinsics.columns[2].x, intrinsics.columns[2].y);                     // scale_x*cx, scale_y*cy

    // Create a depth camera to world matrix. The depth image coordinate system happens to be
    // almost the same as the ARKit camera system, except y is flipped (everything rotated 180
    // degrees about the x axis, which points down in portrait orientation).
    simd_float4x4 rotateDepthToARKit = {
        simd_make_float4(1, 0, 0, 0),
        simd_make_float4(0, 1, 0, 0),
        simd_make_float4(0, 0, 1, 0),
        simd_make_float4(0, 0, 0, 1)
    };
    rotateDepthToARKit.columns[1].y = -1.0; // cos(180)
    rotateDepthToARKit.columns[1].z = 0.0;  // sin(180)
    rotateDepthToARKit.columns[2].y = 0.0;  // -sin(180)
    rotateDepthToARKit.columns[2].z = -1.0; // cos(180)
    simd_float4x4 cameraToWorld = simd_mul(viewMatrix, rotateDepthToARKit);

    // Decay existing
    for (size_t i = 0; i < _cellsWide * _cellsDeep; i++)
    {
        _occupancy[i] *= previousWeight;
    }

    // Check each depth point and update observation count
    float *depthValues = reinterpret_cast<float *>(CVPixelBufferGetBaseAddress(depthMap));
    size_t offsetToNextLine = CVPixelBufferGetBytesPerRow(depthMap) / sizeof(float) - depthWidth;
    for (float y = 0; y < depthHeight; y += 1.0f)
    {
        for (float x = 0; x < depthWidth; x += 1.0f)
        {
            // Fetch depth value at (xi,yi)
            float depth = *depthValues++;
            
            // Works best with values that are not too close or too far (for some reason these
            // tend to be noisy)
            if (depth < minDepth || depth > maxDepth)
            {
                continue;
            }

            // Compute world position
            simd_float2 xy = simd_make_float2(x, y);
            simd_float2 offset = xy - c;                        // (x: x-cx, y: y-cy)
            simd_float2 depthDivF = depth * invF;               // (x: depth/fx, y: depth/fy)
            simd_float2 cameraSpacePosXY = offset * depthDivF;  // (x: depth*(x-cx)/fx, y: depth*(y-cy)/fy)
            simd_float4 cameraSpacePos = simd_make_float4(cameraSpacePosXY.x, cameraSpacePosXY.y, depth, 1.0f);
            simd_float4 worldPos4 = simd_mul(cameraToWorld, cameraSpacePos);
            simd_float3 worldPos = simd_make_float3(worldPos4);

            // Ignore floor and ceiling; constrain to some horizontal slice
            if (worldPos.y < minHeight || worldPos.y > maxHeight)
            {
                continue;
            }

            // Count LiDAR points found
            auto cell = positionToIndices(worldPos);
            size_t idx = linearIndex(cell.first, cell.second);
            _occupancy[idx] += 1.0f * incomingSampleWeight;
        }

        depthValues += offsetToNextLine;
    }

//    for (size_t i = 0; i < _cellsWide * _cellsDeep; i++)
//    {
//        if (_occupancy[i] > 0)
//        {
//            std::cout << i << ": " << _occupancy[i] << std::endl;
//        }
//    }

    CVPixelBufferUnlockBaseAddress(depthMap, 0);
}

void OccupancyMap::updateOccupancyFromCounts(const OccupancyMap &counts, float thresholdAmount)
{
    assert(counts._cellsWide * counts._cellsDeep == _cellsWide * _cellsDeep);
    for (size_t i = 0; i < counts._cellsWide * counts._cellsDeep; i++)
    {
        if (counts._occupancy[i] >= thresholdAmount)
        {
            _occupancy[i] = 1.0f;
        }
    }
}

void OccupancyMap::updateOccupancyFromHeightMap(const float *heights, size_t size, float occupancyHeightThreshold)
{
    if (size != _cellsWide * _cellsDeep)
    {
        std::cout << "[OccupancyMap] Error: Height map dimensions do not match occupancy map" << std::endl;
        return;
    }

    for (size_t i = 0; i < size; i++)
    {
        _occupancy[i] = (heights[i] >= occupancyHeightThreshold ? 1.0f : 0.0f);
    }
}

void OccupancyMap::updateOccupancyFromArray(const float *occupied, size_t size)
{
    if (size != _cellsWide * _cellsDeep)
    {
        std::cout << "[OccupancyMap] Error: Array dimensions do not match occupancy map" << std::endl;
        return;
    }
    memcpy(_occupancy.get(), occupied, size * sizeof(float));
}
