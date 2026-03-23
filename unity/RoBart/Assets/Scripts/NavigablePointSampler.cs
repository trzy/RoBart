using System.Collections.Generic;
using UnityEngine;

/// Samples navigable points from an occupancy map in front of the robot and projects them onto
/// a camera image, matching the logic in the iOS AnnotatingCamera.
public class NavigablePointSampler
{
    public struct Parameters
    {
        /// Half-angle of the forward cone in degrees. Only points within this angle of the
        /// robot's forward direction are considered (iOS default: 25).
        public float ConeAngleDegrees;

        /// Point sampling grid spacing expressed as a multiple of the occupancy map cell size
        /// (iOS uses 0.75m spacing with 0.25m cells = 3).
        public float PointSpacingCells;

        /// Radius around the robot to search for candidate points, in meters (iOS default: 4.0).
        public float SearchRadiusMeters;

        /// Maximum navigable point distance expressed as a multiple of the point spacing in
        /// meters (iOS default: 5, giving 5 × 0.75 = 3.75 m).
        public float MaxDistanceMultiplier;

        public static Parameters Default => new Parameters
        {
            ConeAngleDegrees      = 25f,
            PointSpacingCells     = 3f,
            SearchRadiusMeters    = 4f,
            MaxDistanceMultiplier = 5f,
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
        robotPosition   = robotPosition.XZProject();
        robotForward    = robotForward.XZProject().normalized;

        float cellSize            = map.CellSize;
        float pointSpacingMeters  = parameters.PointSpacingCells * cellSize;
        float maxDistance         = parameters.MaxDistanceMultiplier * pointSpacingMeters;
        int   cellSpacing         = Mathf.Max(1, Mathf.RoundToInt(parameters.PointSpacingCells));
        int   searchRadiusCells   = Mathf.RoundToInt(parameters.SearchRadiusMeters / cellSize);

        OccupancyMap.CellIndices robotCell = map.PositionToCell(robotPosition);

        int minCellX = robotCell.x - searchRadiusCells;
        int maxCellX = robotCell.x + searchRadiusCells;
        int minCellZ = robotCell.z - searchRadiusCells;
        int maxCellZ = robotCell.z + searchRadiusCells;

        var candidates = new List<Vector2>();

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

                // Must be within the maximum distance
                if (distance > maxDistance) continue;

                // Must project onto the screen
                Vector3 screenPoint = camera.WorldToScreenPoint(worldPoint);
                if (screenPoint.z <= 0f) continue;
                if (screenPoint.x < 0f || screenPoint.x >= Screen.width)  continue;
                if (screenPoint.y < 0f || screenPoint.y >= Screen.height) continue;

                // Must have an unobstructed line of sight through the occupancy grid
                if (!IsLineUnobstructed(map, robotCell, cell)) continue;

                float imageX = screenPoint.x;
                float imageY = screenPoint.y;
                candidates.Add(new Vector2(imageX, imageY));
            }
        }

        // Assign sequential IDs starting from firstId
        var result = new AnnotatedPoint[candidates.Count];
        for (int i = 0; i < candidates.Count; i++)
        {
            result[i] = new AnnotatedPoint { id = firstId + i, x = candidates[i].x, y = candidates[i].y };
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
