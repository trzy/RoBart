using System;

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
public struct VectorXZ
{
    public float x;
    public float z;
}

[Serializable]
public struct AnnotatedPoint
{
    public int id;
    public float screenX;
    public float screenY;
    public VectorXZ worldPosition;
}

[Serializable]
public struct AnnotatedImage
{
    public string imageJpegBase64;
    public VectorXZ cameraPosition;
    public VectorXZ cameraForward;
    public AnnotatedPoint[] points;
}

[Serializable]
public struct ObservationsMessage
{
    public string description;
    public AnnotatedImage[] images;

    // Occupancy and last-visited maps (shared grid dimensions)
    public int mapCellsWide;
    public int mapCellsDeep;
    public float mapOriginX;   // world X of the cell (0,0) corner
    public float mapOriginZ;   // world Z of the cell (0,0) corner
    public float mapCellSize;
    public int[] occupancy;      // row-major, 0 = free, 1 = occupied
    public float[] lastVisited;  // row-major, seconds (Time.time), -1 = never visited
}

[Serializable]
public struct VisualTraceSample
{
    public string imageJpegBase64;
    public VectorXZ worldPosition;
    public VectorXZ worldForward;
    public float timestampSeconds;
}

[Serializable]
public struct VisualTraceMessage
{
    public VisualTraceSample[] entries;
}

// OccupancyMapMessage is serialized manually in OccupancyMapBuilder because JsonUtility does
// not support jagged arrays (int[][]) required for pathCells.
// Schema (must match server messages.py):
//   cellsWide : int
//   cellsDeep : int
//   occupancy : float[]   row-major, 0.0 = free, 1.0 = occupied
//   robotCell : int[2]    [cellX, cellZ]
//   pathCells : int[][]   list of [cellX, cellZ] waypoints
