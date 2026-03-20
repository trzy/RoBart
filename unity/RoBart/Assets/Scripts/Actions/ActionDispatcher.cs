using UnityEngine;

public static class ActionDispatcher
{
    public static void Dispatch(object action, IActionHandler handler)
    {
        switch (action)
        {
            case MoveAction a:              handler.OnMoveAction(a); break;
            case MoveToAction a:            handler.OnMoveToAction(a); break;
            case TurnInPlaceAction a:       handler.OnTurnInPlaceAction(a); break;
            case FaceTowardAction a:        handler.OnFaceTowardAction(a); break;
            case FaceTowardHeadingAction a: handler.OnFaceTowardHeadingAction(a); break;
            case Scan360Action a:           handler.OnScan360Action(a); break;
            case TakePhotoAction a:         handler.OnTakePhotoAction(a); break;
            case BackOutAction a:           handler.OnBackOutAction(a); break;
            default:
                Debug.LogError($"ActionDispatcher: unhandled action type {action?.GetType().Name ?? "null"}");
                break;
        }
    }
}
