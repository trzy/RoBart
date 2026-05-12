using System.Collections;
using UnityEngine;

public static class ActionDispatcher
{
    public static IEnumerator Dispatch(object action, IActionHandler handler)
    {
        switch (action)
        {
            case MoveAction a:              return handler.OnMoveAction(a);
            case MoveToAction a:            return handler.OnMoveToAction(a);
            case MoveToPosAction a:         return handler.OnMoveToPosAction(a);
            case MoveToLocationAction a:    return handler.OnMoveToLocationAction(a);
            case TurnInPlaceAction a:       return handler.OnTurnInPlaceAction(a);
            case FaceTowardAction a:        return handler.OnFaceTowardAction(a);
            case FaceTowardPosAction a:     return handler.OnFaceTowardPosAction(a);
            case FaceTowardHeadingAction a: return handler.OnFaceTowardHeadingAction(a);
            case Scan360Action a:           return handler.OnScan360Action(a);
            case TakePhotoAction a:         return handler.OnTakePhotoAction(a);
            case BackOutAction a:           return handler.OnBackOutAction(a);
            default:
                Debug.LogError($"ActionDispatcher: unhandled action type {action?.GetType().Name ?? "null"}");
                return null;
        }
    }
}
