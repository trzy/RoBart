// OccupancyMapBuilder.cs
// RoBart
//
// MonoBehaviour that populates an OccupancyMap by scanning scene geometry
// with Physics.CheckBox on a repeating interval.
//
// Also implements MessageReceivingBehavior so it can respond to
// RequestOccupancyMapMessage by sending back the current map state.

using System.Diagnostics;
using System.Text;
using UnityEngine;

public class OccupancyMapBuilder : MessageReceivingBehavior
{
    [SerializeField] private float _cellSize        = 0.25f;
    [SerializeField] private float _mapSize         = 100f;  // total side length of the occupancy map (meters)
    [SerializeField] private float _scanRegionSize  = 5f;    // side length of the area scanned each interval (meters)
    [SerializeField] private float _scanInterval    = 0.5f;  // seconds between scans
    [SerializeField] private float _bottomHeight    = 0.1f;  // distance above y=0 (floor) where box starts
    [SerializeField] private float _topHeight       = 1.0f;  // distance above y=0 (floor) where box ends
    [SerializeField] private LayerMask _layers;

    public OccupancyMap Map { get; private set; }

    private void Start()
    {
        Map = new OccupancyMap(_mapSize, _cellSize, transform.position);
        InvokeRepeating(nameof(Scan), 0f, _scanInterval);
    }

    private void Scan()
    {
        float boxHalfHeight = (_topHeight - _bottomHeight) / 2f;
        float boxCenterY    = (_bottomHeight + _topHeight) / 2f;
        var   halfExtents   = new Vector3(_cellSize / 2f, boxHalfHeight, _cellSize / 2f);

        // Only update cells within the scan region centred on the robot.
        Vector3 robotPos  = transform.position;
        float   halfScan  = _scanRegionSize / 2f;
        OccupancyMap.CellIndices minCell = Map.PositionToCell(robotPos - new Vector3(halfScan, 0f, halfScan));
        OccupancyMap.CellIndices maxCell = Map.PositionToCell(robotPos + new Vector3(halfScan, 0f, halfScan));

        for (int z = minCell.z; z <= maxCell.z; z++)
        {
            for (int x = minCell.x; x <= maxCell.x; x++)
            {
                Vector3 worldPos = Map.CellToPosition(new OccupancyMap.CellIndices(x, z));
                worldPos.y = boxCenterY;

                bool occupied = Physics.CheckBox(
                    worldPos,
                    halfExtents,
                    Quaternion.identity,
                    _layers,
                    QueryTriggerInteraction.Ignore);

                Map.SetOccupied(x, z, occupied);
            }
        }
    }

    public override void OnRequestOccupancyMap(Net.Session session)
    {
        if (session == null)
            return;

        session.Send(BuildOccupancyMapJson(new OccupancyMap.CellIndices[0]));
    }

    // Builds and encodes an OccupancyMapMessage JSON payload.
    // pathCells: ordered array of cell waypoints to include in the response.
    public byte[] BuildOccupancyMapJson(OccupancyMap.CellIndices[] pathCells)
    {
        OccupancyMap.CellIndices robotCell = Map.PositionToCell(transform.position);

        int totalCells = Map.CellsWide * Map.CellsDeep;
        var sb = new StringBuilder(totalCells * 4 + 256);

        sb.Append("{\"__id\":\"OccupancyMapMessage\"");
        sb.Append(",\"cellsWide\":").Append(Map.CellsWide);
        sb.Append(",\"cellsDeep\":").Append(Map.CellsDeep);
        sb.Append(",\"occupancy\":[");

        bool first = true;
        for (int z = 0; z < Map.CellsDeep; z++)
        {
            for (int x = 0; x < Map.CellsWide; x++)
            {
                if (!first) sb.Append(',');
                sb.Append(Map.IsOccupied(x, z) ? "1.0" : "0.0");
                first = false;
            }
        }

        sb.Append("],\"robotCell\":[")
          .Append(robotCell.x).Append(',').Append(robotCell.z)
          .Append(']');

        sb.Append(",\"pathCells\":[");
        for (int i = 0; i < pathCells.Length; i++)
        {
            if (i > 0) sb.Append(',');
            sb.Append('[').Append(pathCells[i].x).Append(',').Append(pathCells[i].z).Append(']');
        }
        sb.Append(']');

        sb.Append('}');

        return Encoding.UTF8.GetBytes(sb.ToString());
    }
}
