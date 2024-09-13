//
//  FindPath.cpp
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/10/24.
//

#include "FindPath.hpp"
#include <iostream>
#include <queue>
#include <unordered_map>


static void getUnoccupiedNeighbors(std::vector<OccupancyMap::CellIndices> *neighbors, const OccupancyMap &occupancy, OccupancyMap::CellIndices cell)
{
    size_t x = cell.cellX;
    size_t z = cell.cellZ;

    neighbors->clear();

    if (x > 0 && occupancy.at(x - 1, z) == 0)
    {
        neighbors->emplace_back(OccupancyMap::CellIndices(x - 1, z));
    }

    if (x < (occupancy.cellsWide() - 1) && occupancy.at(x + 1, z) == 0)
    {
        neighbors->emplace_back(OccupancyMap::CellIndices(x + 1, z));
    }

    if (z > 0 && occupancy.at(x, z - 1) == 0)
    {
        neighbors->emplace_back(OccupancyMap::CellIndices(x, z - 1));
    }

    if (z < (occupancy.cellsDeep() - 1) && occupancy.at(x, z + 1) == 0)
    {
        neighbors->emplace_back(OccupancyMap::CellIndices(x, z + 1));
    }
}

std::vector<OccupancyMap::CellIndices> findPath(const OccupancyMap &occupancy, simd_float3 from, simd_float3 to)
{
    std::vector<OccupancyMap::CellIndices> path;

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

        getUnoccupiedNeighbors(&neighbors, occupancy, cell);
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
    // Trace complete path back from src to dest
    OccupancyMap::CellIndices currentStep = src;
    do
    {
        path.emplace_back(currentStep);
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

    return path;
}

