namespace Net
{
  public interface IMessageHandler
  {
    // Returns true if message was successfully handled
    bool HandleMessage(Session session, byte[] messageBytes);
  }
}