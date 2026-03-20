public interface IActionHandler
{
    void OnMoveAction(MoveAction action);
    void OnMoveToAction(MoveToAction action);
    void OnTurnInPlaceAction(TurnInPlaceAction action);
    void OnFaceTowardAction(FaceTowardAction action);
    void OnFaceTowardHeadingAction(FaceTowardHeadingAction action);
    void OnScan360Action(Scan360Action action);
    void OnTakePhotoAction(TakePhotoAction action);
    void OnBackOutAction(BackOutAction action);
}
