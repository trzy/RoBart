using System.Collections;

public interface IActionHandler
{
    IEnumerator OnMoveAction(MoveAction action);
    IEnumerator OnMoveToAction(MoveToAction action);
    IEnumerator OnMoveToPosAction(MoveToPosAction action);
    IEnumerator OnTurnInPlaceAction(TurnInPlaceAction action);
    IEnumerator OnFaceTowardAction(FaceTowardAction action);
    IEnumerator OnFaceTowardPosAction(FaceTowardPosAction action);
    IEnumerator OnFaceTowardHeadingAction(FaceTowardHeadingAction action);
    IEnumerator OnScan360Action(Scan360Action action);
    IEnumerator OnTakePhotoAction(TakePhotoAction action);
    IEnumerator OnBackOutAction(BackOutAction action);
}
