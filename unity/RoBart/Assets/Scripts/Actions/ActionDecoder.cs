using UnityEngine;

public static class ActionDecoder
{
    public static object DecodeAction(string json)
    {
        Debug.Log($"ActionDecoder: Received: {json}");
        string type = JsonUtility.FromJson<ActionHeader>(json).type;
        switch (type)
        {
            case "move":            return JsonUtility.FromJson<MoveAction>(json);
            case "moveTo":          return JsonUtility.FromJson<MoveToAction>(json);
            case "moveToPos":       return JsonUtility.FromJson<MoveToPosAction>(json);
            case "moveToLocation":  return JsonUtility.FromJson<MoveToLocationAction>(json);
            case "turnInPlace":     return JsonUtility.FromJson<TurnInPlaceAction>(json);
            case "faceToward":      return JsonUtility.FromJson<FaceTowardAction>(json);
            case "faceTowardPos":   return JsonUtility.FromJson<FaceTowardPosAction>(json);
            case "scan360":         return JsonUtility.FromJson<Scan360Action>(json);
            case "takePhoto":       return JsonUtility.FromJson<TakePhotoAction>(json);
            case "backOut":         return JsonUtility.FromJson<BackOutAction>(json);
            default:
                Debug.LogError($"ActionDecoder: unknown action type \"{type}\"");
                return null;
        }
    }
}
