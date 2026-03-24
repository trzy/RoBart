using System.Collections.Generic;
using UnityEngine;

/// Samples navigable points from an occupancy map in front of the robot and projects them onto
/// a camera image, matching the logic in the iOS AnnotatingCamera.
public class NavigablePointSampler
{
    [System.Serializable]
    public struct Parameters
    {
        /// Half-angle of the forward cone in degrees. Only points within this angle of the
        /// robot's forward direction are considered.
        public float ConeAngleDegrees;

        /// Minimum distance from the robot in meters. Points closer than this are ignored.
        public float MinDistanceMeters;

        /// Maximum distance from the robot in meters. Points farther than this are ignored.
        public float MaxDistanceMeters;

        /// Spacing between sampled grid points in meters. Smaller values produce more points.
        public float PointSpacingMeters;

        public static Parameters Default => new Parameters
        {
            ConeAngleDegrees  = 25f,
            MinDistanceMeters = 0f,
            MaxDistanceMeters = 3.75f,
            PointSpacingMeters = 0.75f,
        };
    }

    /// Sample navigable points from the occupancy map and return them as screen-space
    /// AnnotatedPoint values ready to attach to a captured image.
    ///
    /// robotPosition and robotForward should be the robot's current world-space pose.
    /// camera is used to project world points onto the image; its render target dimensions
    /// determine whether a projected point is on-screen.
    public static AnnotatedPoint[] Sample(
        OccupancyMap map,
        Vector3 robotPosition,
        Vector3 robotForward,
        Camera camera,
        Parameters parameters,
        int firstId = 1)
    {
        // Work on the XZ plane only
        robotPosition = robotPosition.XZProject();
        robotForward  = robotForward.XZProject().normalized;

        float cellSize    = map.CellSize;
        int   cellSpacing = Mathf.Max(1, Mathf.RoundToInt(parameters.PointSpacingMeters / cellSize));
        int   radiusCells = Mathf.RoundToInt(parameters.MaxDistanceMeters / cellSize);

        OccupancyMap.CellIndices robotCell = map.PositionToCell(robotPosition);

        int minCellX = robotCell.x - radiusCells;
        int maxCellX = robotCell.x + radiusCells;
        int minCellZ = robotCell.z - radiusCells;
        int maxCellZ = robotCell.z + radiusCells;

        var candidates = new List<(Vector2 screen, Vector3 world)>();

        for (int cx = minCellX; cx <= maxCellX; cx += cellSpacing)
        {
            for (int cz = minCellZ; cz <= maxCellZ; cz += cellSpacing)
            {
                // Skip out-of-bounds cells
                if (cx < 0 || cx >= map.CellsWide || cz < 0 || cz >= map.CellsDeep)
                    continue;

                var cell = new OccupancyMap.CellIndices(cx, cz);
                Vector3 worldPoint = map.CellToPosition(cell);
                worldPoint.y = robotPosition.y;

                Vector3 toPoint  = (worldPoint - robotPosition).XZProject();
                float   distance = toPoint.magnitude;
                if (distance < 1e-3f) continue;

                Vector3 toPointNorm = toPoint / distance;

                // Must be in the forward half-plane
                if (Vector3.Dot(toPointNorm, robotForward) < 0f) continue;

                // Must be within the cone angle
                if (Vector3.Angle(toPointNorm, robotForward) > parameters.ConeAngleDegrees) continue;

                // Must be within the distance range
                if (distance < parameters.MinDistanceMeters) continue;
                if (distance > parameters.MaxDistanceMeters) continue;

                // Must project onto the screen
                Vector3 screenPoint = camera.WorldToScreenPoint(worldPoint);
                if (screenPoint.z <= 0f) continue;
                if (screenPoint.x < 0f || screenPoint.x >= Screen.width)  continue;
                if (screenPoint.y < 0f || screenPoint.y >= Screen.height) continue;

                // Must have an unobstructed line of sight through the occupancy grid
                if (!IsLineUnobstructed(map, robotCell, cell)) continue;

                candidates.Add((new Vector2(screenPoint.x, screenPoint.y), worldPoint));
            }
        }

        // Assign sequential IDs starting from firstId
        var result = new AnnotatedPoint[candidates.Count];
        for (int i = 0; i < candidates.Count; i++)
        {
            result[i] = new AnnotatedPoint
            {
                id = firstId + i,
                screenX = candidates[i].screen.x,
                screenY = candidates[i].screen.y,
                worldPosition = candidates[i].world
            };
        }
        return result;
    }

    /// Amanatides-Woo 2D voxel traversal. Returns false if any occupied cell lies on the
    /// straight line between from and to (inclusive).
    private static bool IsLineUnobstructed(OccupancyMap map, OccupancyMap.CellIndices from, OccupancyMap.CellIndices to)
    {
        int x = from.x, z = from.z;

        if (x == to.x && z == to.z)
            return !IsOccupiedSafe(map, x, z);

        float vx = to.x - from.x;
        float vz = to.z - from.z;

        int stepX = vx > 0f ? 1 : -1;
        int stepZ = vz > 0f ? 1 : -1;

        // Time to first cell boundary, and time to cross one full cell, in each axis.
        // The ray is parameterised so that t=1 at the destination cell centre.
        float tMaxX   = vx != 0f ? 0.5f / Mathf.Abs(vx) : float.PositiveInfinity;
        float tMaxZ   = vz != 0f ? 0.5f / Mathf.Abs(vz) : float.PositiveInfinity;
        float tDeltaX = vx != 0f ? 1f   / Mathf.Abs(vx) : float.PositiveInfinity;
        float tDeltaZ = vz != 0f ? 1f   / Mathf.Abs(vz) : float.PositiveInfinity;

        while (true)
        {
            if (IsOccupiedSafe(map, x, z)) return false;
            if (x == to.x && z == to.z)   return true;

            if (tMaxX < tMaxZ)
            {
                x     += stepX;
                tMaxX += tDeltaX;
            }
            else
            {
                z     += stepZ;
                tMaxZ += tDeltaZ;
            }
        }
    }

    private static bool IsOccupiedSafe(OccupancyMap map, int x, int z)
    {
        if (x < 0 || x >= map.CellsWide || z < 0 || z >= map.CellsDeep) return true;
        return map.IsOccupied(x, z);
    }
}
