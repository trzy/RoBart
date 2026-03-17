using UnityEngine;

public static class Vector3Extensions
{
    public static Vector3 XZProject(this Vector3 v)
    {
        return new Vector3(v.x, 0, v.z);
    }
}
