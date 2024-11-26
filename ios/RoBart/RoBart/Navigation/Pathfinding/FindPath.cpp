//
//  FindPath.cpp
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

#include "FindPath.hpp"
#include <iostream>
#include <queue>
#include <unordered_map>

/// Given a characteristic radius, determines the side length in cells of the rectangular area to assume as the footprint of the robot.
/// For example, if the cell side length is 0.5 and the radius of the robot's footprint is 0.6, the result should be 3 (a 3x3 area needs
/// to be checked because the robot will be overlapping up to that many cells).
/// - Parameter occupancy: The occupancy map.
/// - Parameter robotRadius: A characteristic robot radius that encompasses the robot's total footprint.
/// - Returns: The side length of the rectangular region, in cells, to represent the robot with. This will be an odd number of at
/// least 1.
static size_t computeFootprintSideLengthInCells(const OccupancyMap &occupancy, float robotRadius)
{
    if (occupancy.cellsWide() * occupancy.cellsDeep() <= 1)
    {
        // Pathological case of a single-celled map
        return 1;
    }

    OccupancyMap::CellIndices center = occupancy.positionToCell(occupancy.centerPoint());
    OccupancyMap::CellIndices limit = occupancy.positionToCell(occupancy.centerPoint() + simd_make_float3(robotRadius, 0, 0));
    size_t cellsOut = limit.cellX - center.cellX;

    // Side length is 1 (center cell) plus the number of cells out in either direction
    return 1 + 2 * cellsOut;
}

/// Check whether we can move into a cell by overlaying a square approximation of the robot's footprint to ensure there are no collisions with nearby cells.
/// - Parameter occupancy: The occupancy map.
/// - Parameter cell: The cell we want to move in; the center of the region that will be checked.
/// - Parameter robotFootprintSideLength: Side length in cell units of the square region with center at `cell` to check. Must be odd.
/// - Returns: True if safe, otherwise false.
static bool isCellSafe(const OccupancyMap &occupancy, OccupancyMap::CellIndices cell, size_t robotFootprintSideLength)
{
    long delta = long(robotFootprintSideLength) / 2;    // note that length will be odd, so we can do this to create a [-delta,+delta] range
    long cellXMin = std::max(long(0), long(cell.cellX) - delta);
    long cellXMax = std::min(cell.cellX + delta, occupancy.cellsWide() - 1);
    long cellZMin = std::max(long(0), long(cell.cellZ) - delta);
    long cellZMax = std::min(cell.cellZ + delta, occupancy.cellsDeep() - 1);
    for (size_t cellZ = cellZMin; cellZ <= cellZMax; cellZ++)
    {
        for (size_t cellX = cellXMin; cellX <= cellXMax; cellX++)
        {
            if (occupancy.at(cellX, cellZ) != 0)
            {
                return false;
            }
        }
    }
    return true;
}

static void getUnoccupiedNeighbors(std::vector<OccupancyMap::CellIndices> *neighbors, const OccupancyMap &occupancy, OccupancyMap::CellIndices cell, size_t robotFootprintSideLength)
{
    size_t x = cell.cellX;
    size_t z = cell.cellZ;

    neighbors->clear();

    OccupancyMap::CellIndices left(x - 1, z);
    OccupancyMap::CellIndices right(x + 1, z);
    OccupancyMap::CellIndices front(x, z - 1);
    OccupancyMap::CellIndices back(x, z + 1);

    if (x > 0 && isCellSafe(occupancy, left, robotFootprintSideLength))
    {
        neighbors->emplace_back(left);
    }

    if (x < (occupancy.cellsWide() - 1) && isCellSafe(occupancy, right, robotFootprintSideLength))
    {
        neighbors->emplace_back(right);
    }

    if (z > 0 && isCellSafe(occupancy, front, robotFootprintSideLength))
    {
        neighbors->emplace_back(front);
    }

    if (z < (occupancy.cellsDeep() - 1) && isCellSafe(occupancy, back, robotFootprintSideLength))
    {
        neighbors->emplace_back(back);
    }
}

std::vector<OccupancyMap::CellIndices> findPath(const OccupancyMap &occupancy, simd_float3 from, simd_float3 to, float robotRadius)
{
    std::vector<OccupancyMap::CellIndices> path;

    size_t robotFootprintSideLength = computeFootprintSideLengthInCells(occupancy, robotRadius);

    OccupancyMap::CellIndices dest = occupancy.positionToCell(to);
    OccupancyMap::CellIndices src = occupancy.positionToCell(from);

    if (occupancy.at(dest) != 0)
    {
        // Destination is occupied, no path
        return path;
    }

    if (dest == src)
    {
        path.emplace_back(src);
        return path;
    }

    std::unordered_map<OccupancyMap::CellIndices, OccupancyMap::CellIndices, OccupancyMap::CellHash> transitions;
    std::queue<OccupancyMap::CellIndices> frontier;
    frontier.push(dest);
    transitions[dest] = dest;

    std::vector<OccupancyMap::CellIndices> neighbors;

    while (!frontier.empty())
    {
        OccupancyMap::CellIndices cell = frontier.front();
        frontier.pop();

        getUnoccupiedNeighbors(&neighbors, occupancy, cell, robotFootprintSideLength);
        for (auto neighbor: neighbors)
        {
            bool alreadyVisited = transitions.find(neighbor) != transitions.end();
            if (alreadyVisited)
            {
                continue;
            }

            transitions[neighbor] = cell;
            if (neighbor == src)
            {
                // We have reached starting point
                goto foundCompletePath;
            }

            frontier.push(neighbor);
        }
    }

    // No path found. Return empty vector.
    return path;

foundCompletePath:
    // Trace complete path back from src to dest. We will include at least src and dest (unless
    // they are the same), and only waypoints where the direction changes.
    OccupancyMap::CellIndices currentStep = src;
    OccupancyMap::CellIndices prevStep = src;
    bool haveDir = false;
    bool movingAlongX = false;
    bool movingAlongZ = false;
    do
    {
        // Remove previous step (except for very first one, src) if the current step will continue
        // along the same direction
        if (haveDir)
        {
            bool dirWillChange = (movingAlongX && (currentStep.cellZ != prevStep.cellZ)) || (movingAlongZ && (currentStep.cellX != prevStep.cellX));
            if (!dirWillChange)
            {
                // This current step will not change the direction, so remove last one
                if (path.size() > 1)
                {
                    path.pop_back();
                }
            }
            else
            {
                // Direction has changed! We must keep the last cell.
                movingAlongX = currentStep.cellZ == prevStep.cellZ;
                movingAlongZ = currentStep.cellX == prevStep.cellX;
            }
        }
        else
        {
            // We don't have a direction yet and can only assess once there are two steps in place
            if (path.size() == 1)
            {
                movingAlongX = currentStep.cellZ == prevStep.cellZ;
                movingAlongZ = currentStep.cellX == prevStep.cellX;
                haveDir = true;
            }
        }

        path.emplace_back(currentStep);
        prevStep = currentStep;

        auto it = transitions.find(currentStep);
        if (it  == transitions.end())
        {
            // Something went very wrong!
            std::cout << "Error: Path is corrupted!" << std::endl;
            path.clear();
            break;
        }
        currentStep = it->second;
    } while (currentStep != dest);
    path.emplace_back(dest);

    return path;
}

