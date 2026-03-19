using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Linq;
using UnityEngine;

public class NetworkManager : Net.JSONMessageSubscriber
{
    [SerializeField]
    private string m_hostname = "localhost";

    [SerializeField]
    private int m_port = 8000;

    [SerializeField]
    private float m_reconnectDelaySeconds = 1;

    private string m_clientID = Guid.NewGuid().ToString();
    private ConcurrentQueue<Action> m_networkQueue = new ConcurrentQueue<Action>();
    private MessageReceivingBehavior[] m_receivers;
    private Net.Session m_session;

    public string clientID
    {
        get
        {
            return m_clientID;
        }
    }

    public bool IsConnected
    {
        get
        {
            return m_session != null && m_session.IsConnected;
        }
    }

    public void Send<T>(ref T jsonSerializableObject) where T : struct
    {
        if (m_session != null)
        {
            m_session.Send(ref jsonSerializableObject);
        }
    }

    protected override void Awake()
    {
        base.Awake();
        TryConnect(0);
    }

    private void Start()
    {
        // Find all message receivers
        m_receivers = FindObjectsOfType<MonoBehaviour>().OfType<MessageReceivingBehavior>().ToArray();
        Debug.LogFormat("Found {0} message receivers", m_receivers.Length);
    }

    private void Update()
    {
        // Process network events
        while (m_networkQueue.TryDequeue(out Action networkEvent))
        {
            networkEvent();
        }
    }

    private void Enqueue(Action networkEvent) => m_networkQueue.Enqueue(networkEvent);

    private void TryConnect(float delaySeconds)
    {
        StartCoroutine(ConnectCoroutine(delaySeconds));
    }

    private IEnumerator ConnectCoroutine(float delaySeconds)
    {
        if (delaySeconds > 0)
        {
            Debug.LogFormat("Next reconnect attempt in {0} seconds", delaySeconds);
            yield return new WaitForSeconds(delaySeconds);
        }
        new Net.TCPClient().Connect(m_hostname, m_port, OnConnected, OnDisconnected, this);
    }

    private void OnConnected(Net.Session session, Exception e)
    {
        Enqueue(() =>
        {
            m_session = session;

            if (session == null)
            {
                // Connect attempt failed
                Debug.LogErrorFormat("Failed to connect to {0}:{1}", m_hostname, m_port);
                TryConnect(m_reconnectDelaySeconds);
                return;
            }

            Debug.LogFormat("Successfully connected to {0}", session);
        });
    }

    private void OnDisconnected(Net.Session session, Exception e)
    {
        Enqueue(() =>
        {
            TryConnect(m_reconnectDelaySeconds);
        });
    }

    [Net.Handler()]
    private void OnUnknownMessage(Net.Session session, string json)
    {
        Debug.LogErrorFormat("Received unknown message from {0}: {1}", session, json);
    }

    [Net.Handler(typeof(HelloMessage))]
    private void OnHelloMessage(Net.Session session, string json)
    {
        HelloMessage msg = JsonUtility.FromJson<HelloMessage>(json);
        Debug.LogFormat("Got hello message: {0}", msg.message);

        HelloMessage reply = new HelloMessage(message: "Hello from RoBart Unity simulator!");
        session.Send(ref reply);
    }

    [Net.Handler(typeof(RequestOccupancyMapMessage))]
    private void OnRequestOccupancyMapMessage(Net.Session session, string json)
    {
        Enqueue(() =>
        {
            Debug.Log("RequestOccupancyMapMessage: received");
            foreach (var receiver in m_receivers)
            {
                receiver.OnRequestOccupancyMap(session);
            }
        });
    }
}
