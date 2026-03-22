using UnityEngine;

namespace ImmersiveTraining.Management
{
    public class SpawnLocations : Singleton<SpawnLocations>
    {
        [SerializeField] private Transform _userSpawnLocation;

        public Transform UserSpawnLocation => _userSpawnLocation;
    }
}
