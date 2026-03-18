/*
 * JSON message wire format
 * ------------------------
 *
 *    Offset    Size (bytes)    Description
 *    ------    ------------    -----------
 *    0         4               Total size of message, N, including these 4
 *                              bytes. Little endian
 *    4         N - 4           JSON payload encoded as a UTF-8 string.
 */

using System;
using System.Collections.Generic;
using System.Linq.Expressions;
using System.Reflection;
using UnityEngine;

namespace Net
{
    public class JSONMessageSubscriber : MonoBehaviour, IMessageHandler
    {
        [Serializable]
        public struct MessageHeader
        {
            public string __id; // message type
        }

        private class HandlerFunctionList
        {
            public List<Action<Session, string>> HandlerFunctions = new List<Action<Session, string>>();
        }

        private readonly Dictionary<string, HandlerFunctionList> m_handlerFunctionsByMessage = new Dictionary<string, HandlerFunctionList>();
        private readonly List<Action<Session, string>> m_unknownHandlerFunctions = new List<Action<Session, string>>();

        protected virtual void Awake()
        {
            object target = this;

            MemberInfo[] members = target.GetType().GetMembers(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static);
            foreach (var member in members)
            {
                Handler[] handlers = member.GetCustomAttributes(typeof(Handler), true) as Handler[];
                if (handlers != null)
                {
                    foreach (Handler handler in handlers)
                    {
                        if (handler.Unknown)
                        {
                            if (!handler.Valid)
                            {
                                continue;
                            }

                            if (MethodHasCorrectSignature(member, handler))
                            {
                                MethodInfo method = member as MethodInfo;
                                AddUnknownHandler(method, handler, target);
                            }
                            else
                            {
                                Debug.LogErrorFormat("JSONMessageHandler: {0}.{1} has incorrect signature and cannot handle unknown messages", member.DeclaringType.FullName, member.Name);
                            }
                        }
                        else
                        {
                            if (MethodHasCorrectSignature(member, handler))
                            {
                                MethodInfo method = member as MethodInfo;
                                AddHandler(method, handler, target);
                            }
                            else
                            {
                                Debug.LogErrorFormat("JSONMessageHandler: {0}.{1} has incorrect signature and cannot handle '{2}' messages", member.DeclaringType.FullName, member.Name, handler.MessageType);
                            }
                        }
                    }
                }
            }
        }

        public bool HandleMessage(Session session, byte[] messageBytes)
        {
            byte[] payloadBytes = Utils.GetMessagePayload(messageBytes);

            if (payloadBytes.Length < 1)
            {
                Debug.LogError("JSONMessageHandler: Received an empty payload");
                return false;
            }
            string json;
            try
            {
                json = System.Text.Encoding.UTF8.GetString(payloadBytes, 0, payloadBytes.Length);
            }
            catch
            {
                Debug.LogError("JSONMessageHandler: Unable to decode JSON payload to extract message type");
                return false;
            }

            // Attempt to decode "messageType" field to determine type
            MessageHeader header = JsonUtility.FromJson<MessageHeader>(json);
            bool messageTypeKnown = true;
            if (header.__id == null || header.__id.Length <= 0)
            {
                messageTypeKnown = false;
                Debug.LogWarning("JSONMessageHandler: Received a JSON payload without required 'messageType' field");
            }

            // Dispatch the message
            HandlerFunctionList handlerFunctions;
            if (messageTypeKnown && m_handlerFunctionsByMessage.TryGetValue(header.__id, out handlerFunctions) && handlerFunctions.HandlerFunctions.Count > 0)
            {
                foreach (var HandlerFunction in handlerFunctions.HandlerFunctions)
                {
                    HandlerFunction(session, json);
                }
                return true;
            }
            else
            {
                foreach (var UnknownHandlerFunction in m_unknownHandlerFunctions)
                {
                    UnknownHandlerFunction(session, json);
                }
                return false;
            }
        }

        private bool MethodHasCorrectSignature(MemberInfo member, Handler handler)
        {
            MethodInfo method = member as MethodInfo;
            if (method != null)
            {
                ParameterInfo[] parameters = method.GetParameters();
                bool notStatic = !method.IsStatic;
                bool correctReturnType = method.ReturnType == typeof(void);
                bool correctParameters =
                    parameters.Length == 2 &&
                    parameters[0].ParameterType == typeof(Session) &&
                    !parameters[0].IsOut &&
                    parameters[1].ParameterType == typeof(string) &&
                    !parameters[1].IsOut;
                return notStatic && correctReturnType && correctParameters;
            }
            else
            {
                return false;
            }
        }

        private void AddHandler(MethodInfo method, Handler handler, object target)
        {
            ParameterInfo[] parameters = method.GetParameters();
            Type delegateType = Expression.GetActionType(new Type[] { parameters[0].ParameterType, parameters[1].ParameterType });
#if !NETFX_CORE
            Delegate lambda = Delegate.CreateDelegate(delegateType, target, method.Name);
#else
            Delegate lambda = method.CreateDelegate(delegateType, target);
#endif
            Action<Session, string> MessageHandlerFunction = lambda as Action<Session, string>;

            // Create a new list of handlers for this message type if it does not already exist
            HandlerFunctionList handlerFunctions;
            if (!m_handlerFunctionsByMessage.TryGetValue(handler.MessageType, out handlerFunctions))
            {
                m_handlerFunctionsByMessage.Add(handler.MessageType, new HandlerFunctionList());
            }

            // Add this handler to the list of handlers for this message type
            handlerFunctions = m_handlerFunctionsByMessage[handler.MessageType];
            handlerFunctions.HandlerFunctions.Add(MessageHandlerFunction);

            Debug.LogFormat("Registered handler for JSON message: {0}", handler.MessageType);
        }

        private void AddUnknownHandler(MethodInfo method, Handler handler, object target)
        {
            ParameterInfo[] parameters = method.GetParameters();
            Type delegateType = Expression.GetActionType(new Type[] { parameters[0].ParameterType, parameters[1].ParameterType });
#if !NETFX_CORE
            Delegate lambda = Delegate.CreateDelegate(delegateType, target, method.Name);
#else
            Delegate lambda = method.CreateDelegate(delegateType, target);
#endif
            Action<Session, string> UnknownMessageHandlerFunction = lambda as Action<Session, string>;
            m_unknownHandlerFunctions.Add(UnknownMessageHandlerFunction);
        }
    }
}