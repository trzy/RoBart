using System.Collections.Generic;
using UnityEngine;

/// Stores unique landmark world positions with deduplication.
/// When a new candidate is within dedupRadius of an existing landmark,
/// the existing landmark's ID is reused instead of allocating a new one.
public class LandmarkStore
{
    private readonly List<Vector3> _points = new List<Vector3>();
    private readonly float _dedupRadius;
    private readonly float _dedupRadiusSqr;

    public LandmarkStore(float dedupRadius)
    {
        _dedupRadius = dedupRadius;
        _dedupRadiusSqr = dedupRadius * dedupRadius;
    }

    public int Count => _points.Count;

    public Vector3 this[int id] => _points[id];

    public bool IsValidId(int id) => id >= 0 && id < _points.Count;

    /// Returns the ID of the closest existing landmark within dedupRadius,
    /// or allocates a new ID if none is close enough.
    public int GetOrAdd(Vector3 worldPosition)
    {
        float bestDistSqr = float.MaxValue;
        int bestId = -1;

        for (int i = 0; i < _points.Count; i++)
        {
            float dx = _points[i].x - worldPosition.x;
            float dz = _points[i].z - worldPosition.z;
            float distSqr = dx * dx + dz * dz;
            if (distSqr < _dedupRadiusSqr && distSqr < bestDistSqr)
            {
                bestDistSqr = distSqr;
                bestId = i;
            }
        }

        if (bestId >= 0)
            return bestId;

        int newId = _points.Count;
        _points.Add(worldPosition);
        return newId;
    }

    /// Post-processes the output of NavigablePointSampler.Sample():
    /// remaps each candidate's ID via GetOrAdd, and drops duplicates
    /// within the same batch (two candidates that resolve to the same ID).
    public AnnotatedPoint[] Resolve(AnnotatedPoint[] candidates)
    {
        var seen = new HashSet<int>();
        var result = new List<AnnotatedPoint>(candidates.Length);

        for (int i = 0; i < candidates.Length; i++)
        {
            var point = candidates[i];
            var worldPos = new Vector3(point.worldPosition.x, 0, point.worldPosition.z);
            int id = GetOrAdd(worldPos);

            if (!seen.Add(id))
                continue; // already used this landmark in this batch

            point.id = id;
            result.Add(point);
        }

        return result.ToArray();
    }
}
