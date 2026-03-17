using System;

public struct ActionHeader
{
    public string action;
}

public struct MoveAction
{
    public float distance;
}

public struct MoveToAction
{
    public float pointNumber;
}

public struct TurnInPlaceAction
{
    public float degrees;
}

public struct FaceTowardAction
{
    public float pointNumber;
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