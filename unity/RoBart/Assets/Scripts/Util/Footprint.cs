using UnityEngine;

/// Computes the robot's XZ footprint radius from its BoxCollider, matching the iOS formula:
/// radius = 0.5 * max(robotBounds.x, robotBounds.z)
public static class Footprint
{
    public static float GetRadius(GameObject robot)
    {
        BoxCollider col = robot.GetComponentInChildren<BoxCollider>();
        Bounds b = col.bounds;
        return 0.5f * Mathf.Max(b.size.x, b.size.z);
    }
}
