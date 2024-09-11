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


typedef std::pair<size_t, size_t> cell_t;

static void getUnoccupiedNeighbors(std::vector<cell_t> *neighbors, const OccupancyMap &occupancy, cell_t cell)
{
    size_t x = cell.first;
    size_t z = cell.second;

    neighbors->clear();

    if (x > 0 && occupancy.at(x - 1, z) == 0)
    {
        neighbors->emplace_back(cell_t(x - 1, z));
    }

    if (x < (occupancy.cellsWide() - 1) && occupancy.at(x + 1, z) == 0)
    {
        neighbors->emplace_back(cell_t(x + 1, z));
    }

    if (z > 0 && occupancy.at(x, z - 1) == 0)
    {
        neighbors->emplace_back(cell_t(x, z - 1));
    }

    if (z < (occupancy.cellsDeep() - 1) && occupancy.at(x, z + 1) == 0)
    {
        neighbors->emplace_back(cell_t(x, z + 1));
    }
}

std::vector<std::pair<size_t, size_t>> findPath(const OccupancyMap &occupancy, simd_float3 from, simd_float3 to)
{
    std::vector<std::pair<size_t, size_t>> path;

    cell_t dest = occupancy.positionToIndices(to);
    cell_t src = occupancy.positionToIndices(from);

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

    std::unordered_map<cell_t, cell_t, OccupancyMap::CellHash> transitions;
    std::queue<cell_t> frontier;
    frontier.push(dest);
    transitions[dest] = dest;

    std::vector<cell_t> neighbors;

    while (!frontier.empty())
    {
        cell_t cell = frontier.front();
        frontier.pop();

        getUnoccupiedNeighbors(&neighbors, occupancy, cell);
        for (cell_t neighbor: neighbors)
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
    cell_t currentStep = src;
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

