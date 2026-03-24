using System;
using UnityEngine;

[Serializable]
public struct HelloMessage
{
    public string message;

    public HelloMessage(string message)
    {
        this.message = message;
    }
}

[Serializable]
public struct RequestOccupancyMapMessage
{
}

[Serializable]
public struct ActionsMessage
{
    public string[] actions;
}

[Serializable]
public struct AnnotatedPoint
{
    public int id;
    public float screenX;
    public float screenY;
    public Vector3 worldPosition;
}

[Serializable]
public struct AnnotatedImage
{
    public string imageJpegBase64;
    public AnnotatedPoint[] points;
}

[Serializable]
public struct ObservationsMessage
{
    public string description;
    public AnnotatedImage[] images;
}

// OccupancyMapMessage is serialized manually in OccupancyMapBuilder because JsonUtility does
// not support jagged arrays (int[][]) required for pathCells.
// Schema (must match server messages.py):
//   cellsWide : int
//   cellsDeep : int
//   occupancy : float[]   row-major, 0.0 = free, 1.0 = occupied
//   robotCell : int[2]    [cellX, cellZ]
//   pathCells : int[][]   list of [cellX, cellZ] waypoints
