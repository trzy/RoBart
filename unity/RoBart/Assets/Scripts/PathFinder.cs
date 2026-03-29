// PathFinder.cs
// RoBart
//
// BFS pathfinder — direct C# port of FindPath.cpp.
// Searches from destination toward source so the transitions map enables
// forward path reconstruction.

using System.Collections.Generic;
using UnityEngine;

public static class PathFinder
{
    public static List<Vector3> FindPath(OccupancyMap<bool> map, Vector3 from, Vector3 to, float robotRadius)
    {
        var path = new List<Vector3>();

        CellIndices src  = map.PositionToCell(from);
        CellIndices dest = map.PositionToCell(to);

        if (map.Get(dest.x, dest.z))
        {
            // Destination is occupied — no path.
            return path;
        }

        if (dest == src)
        {
            path.Add(map.CellToPosition(src));
            return path;
        }

        int footprint = ComputeFootprintSideLengthInCells(map, robotRadius);

        var transitions = new Dictionary<CellIndices, CellIndices>();
        var frontier    = new Queue<CellIndices>();
        frontier.Enqueue(dest);
        transitions[dest] = dest;

        var neighbors = new List<CellIndices>(4);

        while (frontier.Count > 0)
        {
            CellIndices cell = frontier.Dequeue();

            GetUnoccupiedNeighbors(neighbors, map, cell, footprint);
            foreach (var neighbor in neighbors)
            {
                if (transitions.ContainsKey(neighbor))
                    continue;

                transitions[neighbor] = cell;

                if (neighbor == src)
                    goto FoundCompletePath;

                frontier.Enqueue(neighbor);
            }
        }

        // No path found — return empty list.
        return path;

FoundCompletePath:
        // Trace path from src back to dest, keeping only direction-change waypoints.
        var cellPath = new List<CellIndices>();

        CellIndices currentStep = src;
        CellIndices prevStep    = src;
        bool haveDir     = false;
        bool movingAlongX = false;
        bool movingAlongZ = false;

        do
        {
            if (haveDir)
            {
                bool dirWillChange =
                    (movingAlongX && currentStep.z != prevStep.z) ||
                    (movingAlongZ && currentStep.x != prevStep.x);

                if (!dirWillChange)
                {
                    // Still moving in the same direction — drop the previous waypoint.
                    if (cellPath.Count > 1)
                        cellPath.RemoveAt(cellPath.Count - 1);
                }
                else
                {
                    // Direction changed — keep previous waypoint and update direction.
                    movingAlongX = currentStep.z == prevStep.z;
                    movingAlongZ = currentStep.x == prevStep.x;
                }
            }
            else
            {
                // Direction only determinable once two steps are in the list.
                if (cellPath.Count == 1)
                {
                    movingAlongX = currentStep.z == prevStep.z;
                    movingAlongZ = currentStep.x == prevStep.x;
                    haveDir = true;
                }
            }

            cellPath.Add(currentStep);
            prevStep = currentStep;

            if (!transitions.TryGetValue(currentStep, out currentStep))
            {
                Debug.LogError("PathFinder: path is corrupted!");
                return new List<Vector3>();
            }
        } while (currentStep != dest);

        cellPath.Add(dest);

        foreach (var cell in cellPath)
            path.Add(map.CellToPosition(cell));

        return path;
    }

    // ---------------------------------------------------------------------------

    private static int ComputeFootprintSideLengthInCells(OccupancyMap<bool> map, float robotRadius)
    {
        if (map.CellsWide * map.CellsDeep <= 1)
            return 1;

        CellIndices center = map.PositionToCell(map.Center);
        CellIndices limit  = map.PositionToCell(map.Center + new Vector3(robotRadius, 0f, 0f));
        int cellsOut = limit.x - center.x;
        return 1 + 2 * cellsOut;
    }

    private static bool IsCellSafe(OccupancyMap<bool> map, CellIndices cell, int footprint)
    {
        int delta    = footprint / 2;
        int xMin = Mathf.Max(0, cell.x - delta);
        int xMax = Mathf.Min(cell.x + delta, map.CellsWide - 1);
        int zMin = Mathf.Max(0, cell.z - delta);
        int zMax = Mathf.Min(cell.z + delta, map.CellsDeep - 1);

        for (int z = zMin; z <= zMax; z++)
        {
            for (int x = xMin; x <= xMax; x++)
            {
                if (map.Get(x, z))
                    return false;
            }
        }
        return true;
    }

    private static void GetUnoccupiedNeighbors(
        List<CellIndices> result,
        OccupancyMap<bool> map,
        CellIndices cell,
        int footprint)
    {
        result.Clear();

        int x = cell.x;
        int z = cell.z;

        var left  = new CellIndices(x - 1, z);
        var right = new CellIndices(x + 1, z);
        var front = new CellIndices(x, z - 1);
        var back  = new CellIndices(x, z + 1);

        if (x > 0 && IsCellSafe(map, left, footprint))
            result.Add(left);

        if (x < map.CellsWide - 1 && IsCellSafe(map, right, footprint))
            result.Add(right);

        if (z > 0 && IsCellSafe(map, front, footprint))
            result.Add(front);

        if (z < map.CellsDeep - 1 && IsCellSafe(map, back, footprint))
            result.Add(back);
    }
}
