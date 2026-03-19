// OccupancyMap.cs
// RoBart
//
// 2D occupancy grid with cell<->world coordinate conversions.
// Plain C# port of the relevant parts of OccupancyMap.hpp / OccupancyMap.cpp.

using System;
using UnityEngine;

public class OccupancyMap
{
    public struct CellIndices : IEquatable<CellIndices>
    {
        public int x;
        public int z;

        public CellIndices(int x, int z)
        {
            this.x = x;
            this.z = z;
        }

        public bool Equals(CellIndices other) => x == other.x && z == other.z;

        public override bool Equals(object obj) => obj is CellIndices other && Equals(other);

        public override int GetHashCode()
        {
            unchecked
            {
                return x * 397 ^ z;
            }
        }

        public static bool operator ==(CellIndices a, CellIndices b) => a.x == b.x && a.z == b.z;
        public static bool operator !=(CellIndices a, CellIndices b) => !(a == b);
    }

    private readonly float _regionSize;
    private readonly float _cellSize;
    private Vector3 _center;
    private readonly int _cellsWide;
    private readonly int _cellsDeep;
    private readonly bool[] _cells;

    public int CellsWide => _cellsWide;
    public int CellsDeep => _cellsDeep;
    public float CellSize => _cellSize;
    public Vector3 Center => _center;

    public OccupancyMap(float regionSize, float cellSize, Vector3 center)
    {
        _regionSize = regionSize;
        _cellSize = cellSize;
        _center = center;
        _cellsWide = _cellsDeep = Mathf.RoundToInt(regionSize / cellSize);
        _cells = new bool[_cellsWide * _cellsDeep];
    }

    /// <summary>Updates the map center and clears all occupancy data.</summary>
    public void Recenter(Vector3 newCenter)
    {
        _center = newCenter;
        Array.Clear(_cells, 0, _cells.Length);
    }

    /// <summary>Converts a world-space position to cell indices, clamped to the map boundary.</summary>
    public CellIndices PositionToCell(Vector3 pos)
    {
        float originX = _center.x - _regionSize / 2f;
        float originZ = _center.z - _regionSize / 2f;
        int cellX = Mathf.FloorToInt((pos.x - originX) / _cellSize);
        int cellZ = Mathf.FloorToInt((pos.z - originZ) / _cellSize);
        cellX = Mathf.Clamp(cellX, 0, _cellsWide - 1);
        cellZ = Mathf.Clamp(cellZ, 0, _cellsDeep - 1);
        return new CellIndices(cellX, cellZ);
    }

    /// <summary>Converts cell indices to the world-space center of that cell.</summary>
    public Vector3 CellToPosition(CellIndices cell)
    {
        float originX = _center.x - _regionSize / 2f;
        float originZ = _center.z - _regionSize / 2f;
        float x = originX + (cell.x + 0.5f) * _cellSize;
        float z = originZ + (cell.z + 0.5f) * _cellSize;
        return new Vector3(x, _center.y, z);
    }

    public bool IsOccupied(int x, int z) => _cells[z * _cellsWide + x];

    public void SetOccupied(int x, int z, bool value) => _cells[z * _cellsWide + x] = value;
}
