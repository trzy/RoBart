using UnityEngine;

public class MessageReceivingBehavior : MonoBehaviour
{
    public virtual void OnConnect(Net.Session session)
    {
    }

    public virtual void OnDisconnect(Net.Session session)
    {
    }

    public virtual void OnRequestOccupancyMap(Net.Session session)
    {
    }

    public virtual void OnActionsMessage(Net.Session session, ActionsMessage msg)
    {
    }
}
