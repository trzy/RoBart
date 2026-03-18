using System;
using System.Reflection;
using UnityEngine;

public static class TransportJSONExtensions
{
    public static void Send<T>(this Net.Session session, ref T jsonSerializableObject) where T : struct
    {
        string json = JsonUtility.ToJson(jsonSerializableObject);
        if (json == null || json.Length == 0)
        {
            Debug.LogError("Session: Message not sent because JSON encoding failed");
            return;
        }

        // Sanity check to ensure JSON was produced
        if (json[0] != '{')
        {
            Debug.LogError("Session: Message did not encode as a JSON object");
            return;
        }

        // Automatically insert the messageType field based on the type name. Must
        // handle special case of empty JSON.
        string messageType = jsonSerializableObject.GetType().Name;
        string jsonWithHeader = "{\"__id\":\"" + messageType + "\"";
        bool isEmpty = json == "{}";
        if (isEmpty)
        {
            jsonWithHeader += "}";
        }
        else
        {
            jsonWithHeader += "," + json.Substring(1);
        }

        // Convert to byte array and send
        byte[] payloadBytes = System.Text.Encoding.UTF8.GetBytes(jsonWithHeader);
        session.Send(payloadBytes);
    }
}