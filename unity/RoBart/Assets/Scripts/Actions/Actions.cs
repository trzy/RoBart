public struct ActionHeader
{
    public string type;
}

public struct MoveAction
{
    public float distance;
}

public struct MoveToAction
{
    public int pointNumber;
}

public struct MoveToPosAction
{
    public float x;
    public float z;
}

public struct TurnInPlaceAction
{
    public float degrees;
}

public struct FaceTowardAction
{
    public int pointNumber;
}

public struct FaceTowardPosAction
{
    public float x;
    public float z;
}

public struct FaceTowardHeadingAction
{
    public float headingDegrees;
}

public struct Scan360Action
{
}

public struct TakePhotoAction
{
}

public struct BackOutAction
{
}
