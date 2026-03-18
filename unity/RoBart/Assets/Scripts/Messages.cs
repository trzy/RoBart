using System;

[Serializable]
public struct HelloMessage
{
    public string message;

    public HelloMessage(string message)
    {
        this.message = message;
    }
}

[Serializable]
public struct RequestOccupancyMapMessage
{
}
