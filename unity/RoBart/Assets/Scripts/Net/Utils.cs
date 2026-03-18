using System;
using UnityEngine;

namespace Net
{
    public static class Utils
    {
        public static UInt32 GetMessageSize(byte[] messageBytes)
        {
            UInt32 size = ((UInt32)messageBytes[3]) << 24;
            size |= ((UInt32)messageBytes[2]) << 16;
            size |= ((UInt32)messageBytes[1]) << 8;
            size |= ((UInt32)messageBytes[0]) << 0;
            return size;
        }

        public static byte[] GetMessagePayload(byte[] messageBytes)
        {
            Debug.Assert(messageBytes.Length >= 4, "Message is truncated");
            UInt32 totalSize = GetMessageSize(messageBytes);
            Debug.Assert(totalSize == messageBytes.Length, "Message length does not match embedded size prefix");
            UInt32 payloadSize = totalSize - 4;
            byte[] payload = new byte[payloadSize];
            Buffer.BlockCopy(messageBytes, 4, payload, 0, (int)payloadSize);
            return payload;
        }
    }
}