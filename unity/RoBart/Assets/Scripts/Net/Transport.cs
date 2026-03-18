using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using UnityEngine;

namespace Net
{
    public class MessageTruncatedException : Exception
    {
        public MessageTruncatedException()
        {
        }

        public MessageTruncatedException(string message)
          : base(message)
        {
        }

        public MessageTruncatedException(string message, Exception inner)
          : base(message, inner)
        {
        }
    }

    public class SessionRestartException : Exception
    {
        public SessionRestartException()
        {
        }

        public SessionRestartException(string message)
          : base(message)
        {
        }

        public SessionRestartException(string message, Exception inner)
          : base(message, inner)
        {
        }
    }

    public class ServerRestartException : Exception
    {
        public ServerRestartException()
        {
        }

        public ServerRestartException(string message)
          : base(message)
        {
        }

        public ServerRestartException(string message, Exception inner)
          : base(message, inner)
        {
        }
    }

    //TODO: these somehow keep themselves alive
    public class Session
    {
        private TcpClient m_tcpClient;
        private NetworkStream m_stream;
        private readonly EndPoint m_remoteEndpoint;
        private readonly object m_lock = new object();
        private Action<Session, Exception> m_DisconnectHandler;
        private IMessageHandler m_messageHandler;
        private byte[] m_sizePrefix = new byte[4];
        private int m_sizePrefixBytesReceived = 0;
        private byte[] m_messageBuffer = null;
        private int m_messageBytesReceived = 0;

        internal Session(TcpClient tcpClient, Action<Session, Exception> DisconnectHandler, IMessageHandler messageHandler)
        {
            m_DisconnectHandler = DisconnectHandler != null ? DisconnectHandler : (Session session, Exception e) => { };
            m_messageHandler = messageHandler;
            m_tcpClient = tcpClient;
            m_tcpClient.NoDelay = true;
            m_tcpClient.SendBufferSize = 1024 * 1024;
            m_tcpClient.ReceiveBufferSize = 1024 * 1024;
            m_stream = m_tcpClient.GetStream();
            m_remoteEndpoint = m_tcpClient.Client.RemoteEndPoint;
        }

        ~Session()
        {
            Stop();
            m_stream = null;
        }

        public override string ToString()
        {
            return RemoteEndpoint.ToString();
        }

        private bool IsStopped()
        {
            return m_tcpClient == null;
        }

        public bool IsConnected
        {
            get
            {
                return m_tcpClient.Connected;
            }
        }

        public EndPoint RemoteEndpoint
        {
            get
            {
                return m_remoteEndpoint;
            }
        }

        internal void Start()
        {
            lock (m_lock)
            {
                if (IsStopped())
                {
                    throw new SessionRestartException("Session has been closed and cannot be restarted");
                }
            }

            m_sizePrefixBytesReceived = 0;
            BeginSizePrefix();
        }

        public void Stop()
        {
            lock (m_lock)
            {
                m_DisconnectHandler = null;
                if (IsStopped())
                {
                    return;
                }
                m_tcpClient.Close();
                m_tcpClient = null;
                m_stream.Close(); // not nulled out in case another thread calls Send() after session stopped
                m_messageHandler = null;
            }
        }

        public void Send(byte[] payloadBytes)
        {
            try
            {
                // Send total message size followed by payload
                UInt32 totalSize = 4 + (UInt32)payloadBytes.Length;
                byte[] sizePrefix = new byte[4];
                sizePrefix[0] = (byte)(totalSize & 0xff);
                sizePrefix[1] = (byte)((totalSize >> 8) & 0xff);
                sizePrefix[2] = (byte)((totalSize >> 16) & 0xff);
                sizePrefix[3] = (byte)((totalSize >> 24) & 0xff);
                m_stream.Write(sizePrefix, 0, sizePrefix.Length);
                m_stream.Write(payloadBytes, 0, payloadBytes.Length);
            }
            catch (ArgumentNullException e)
            {
                Debug.LogErrorFormat("Session: ArgumentNullException: {0}", e);
                throw;
            }
            catch (ObjectDisposedException e)
            {
                // This can occur if writes were enqueued after a disconnect and should be treated as non-fatal
                Debug.LogFormat("Session: ObjectDisposedException (most likely due to a write after Session stopped): {0}", e);
            }
            catch (IOException e)
            {
                lock (m_lock)
                {
                    Debug.LogErrorFormat("Session: IOException: {0}", e);
                    m_DisconnectHandler?.Invoke(this, e);
                    Stop();
                }
            }
            catch (SocketException e)
            {
                lock (m_lock)
                {
                    Debug.LogErrorFormat("Session: SocketException: {0}", e);
                    m_DisconnectHandler?.Invoke(this, e);
                    Stop();
                }
            }
            catch (Exception e)
            {
                lock (m_lock)
                {
                    Debug.LogErrorFormat("Session: Unknown exception: {0}", e);
                    m_DisconnectHandler?.Invoke(this, e);
                    Stop();
                }
            }
        }

        private void AllocateNewMessageBuffer()
        {
            // Message buffer holds the entire message, including the size prefix
            m_messageBuffer = new byte[Utils.GetMessageSize(m_sizePrefix)];
            Buffer.BlockCopy(m_sizePrefix, 0, m_messageBuffer, 0, m_sizePrefix.Length);
            m_messageBytesReceived = m_sizePrefix.Length;
        }

        private void BeginSizePrefix()
        {
            int bytesRemaining = m_sizePrefix.Length - m_sizePrefixBytesReceived;
            m_stream.BeginRead(m_sizePrefix, m_sizePrefixBytesReceived, bytesRemaining, new AsyncCallback(FinishSizePrefix), m_stream);
        }

        private void FinishSizePrefix(IAsyncResult result)
        {
            int numBytesReceived = 0;

            try
            {
                numBytesReceived = m_stream.EndRead(result);
            }
            catch (Exception e)
            {
                lock (m_lock)
                {
                    m_DisconnectHandler?.Invoke(this, e);
                    Stop();
                }
                return;
            }

            if (numBytesReceived == 0)
            {
                lock (m_lock)
                {
                    string errorMessage = string.Format("Connection closed (read {0} of {1} bytes expected)", m_sizePrefixBytesReceived, m_sizePrefix.Length);
                    m_DisconnectHandler?.Invoke(this, new MessageTruncatedException(errorMessage));
                    IsStopped();
                }
                return;
            }

            m_sizePrefixBytesReceived += numBytesReceived;

            if (m_sizePrefixBytesReceived == m_sizePrefix.Length)
            {
                // Size of message obtained; read payload next
                AllocateNewMessageBuffer();
                BeginPayload();
            }
            else
            {
                // Still more to receive...
                BeginSizePrefix();
            }
        }

        private void BeginPayload()
        {
            int bytesRemaining = m_messageBuffer.Length - m_messageBytesReceived;
            m_stream.BeginRead(m_messageBuffer, m_messageBytesReceived, bytesRemaining, new AsyncCallback(FinishPayload), m_stream);
        }

        private void FinishPayload(IAsyncResult result)
        {
            int numBytesReceived = 0;

            try
            {
                numBytesReceived = m_stream.EndRead(result);
            }
            catch (Exception e)
            {
                lock (m_lock)
                {
                    m_DisconnectHandler?.Invoke(this, e);
                    Stop();
                }
                return;
            }

            UInt32 totalMessageSize = Utils.GetMessageSize(m_sizePrefix);
            bool hasBody = totalMessageSize > m_sizePrefix.Length;

            if (numBytesReceived == 0 && hasBody)
            {
                lock (m_lock)
                {
                    string errorMessage = string.Format("Connection closed (read {0} of {1} bytes expected)", m_messageBytesReceived, m_messageBuffer.Length);
                    m_DisconnectHandler?.Invoke(this, new MessageTruncatedException(errorMessage));
                }
                return;
            }

            m_messageBytesReceived += numBytesReceived;

            if (m_messageBytesReceived == m_messageBuffer.Length)
            {
                // Obtained complete message
                if (m_messageHandler != null)
                {
                    m_messageHandler.HandleMessage(this, m_messageBuffer);
                }

                // Read next message
                m_messageBuffer = null;
                m_sizePrefixBytesReceived = 0;
                BeginSizePrefix();
            }
            else
            {
                // Still more to receive...
                BeginPayload();
            }
        }
    }

    public class TCPClient
    {
        public Session Connect(string hostname, int port, Action<Session, Exception> ConnectHandler, Action<Session, Exception> DisconnectHandler, IMessageHandler messageHandler)
        {
            bool failed = true;
            Exception exception = null;
            Session session = null;

            try
            {
                TcpClient client = new TcpClient(hostname, port);
                session = new Session(client, DisconnectHandler, messageHandler);
                session.Start();
                failed = false;
            }
            catch (ArgumentNullException e)
            {
                exception = e;
            }
            catch (SocketException e)
            {
                // Connections that are refused trigger this exception
                exception = e;
            }

            if (failed)
            {
                // We indicate connect failures by calling the ConnectHandler with a null session
                ConnectHandler(null, exception);
            }
            else
            {
                // Connection must have succeeded
                ConnectHandler(session, exception);
            }

            return session;
        }
    }

    public class TCPServer
    {
        private TcpListener m_tcpListener = null;
        private object m_lock = new object();
        private HashSet<Session> m_pendingSessions = new HashSet<Session>();

        private class AcceptData
        {
            public TcpListener tcpListener;
            public int port;
            public Action<Session> AcceptHandler;
            public Action<Session, Exception> DisconnectHandler;
            public IMessageHandler messageHandler;

            public AcceptData(TcpListener tcpListener, int port, Action<Session> AcceptHandler, Action<Session, Exception> DisconnectHandler, IMessageHandler messageHandler)
            {
                this.tcpListener = tcpListener;
                this.port = port;
                this.AcceptHandler = AcceptHandler;
                this.DisconnectHandler = DisconnectHandler;
                this.messageHandler = messageHandler;
            }
        }

        ~TCPServer()
        {
            Stop();
        }

        public void Start(int port, Action<Session> AcceptHandler, Action<Session, Exception> DisconnectHandler, IMessageHandler messageHandler)
        {
            if (m_tcpListener != null)
            {
                throw new ServerRestartException("Server already started");
            }
            StartAccepting(port, AcceptHandler, DisconnectHandler, messageHandler);
        }

        public void Stop()
        {
            if (m_tcpListener != null)
            {
                m_tcpListener.Stop();
                m_tcpListener = null;
            }
        }

        // Listens on all interfaces
        private void StartAccepting(int port, Action<Session> AcceptHandler, Action<Session, Exception> DisconnectHandler, IMessageHandler messageHandler)
        {
            if (m_tcpListener == null)
            {
                m_tcpListener = new TcpListener(IPAddress.Any, port);
                m_tcpListener.Server.NoDelay = true;
                m_tcpListener.Start();
            }

            AcceptData data = new AcceptData(m_tcpListener, port, AcceptHandler, DisconnectHandler, messageHandler);
            m_tcpListener.BeginAcceptTcpClient(new AsyncCallback(FinishAccept), data);
        }

        // Listen on specific interface
        private void StartAccepting(string interfaceIP, int port, Action<Session> AcceptHandler, Action<Session, Exception> DisconnectHandler, IMessageHandler messageHandler)
        {
            if (m_tcpListener == null)
            {
                IPEndPoint ourEndPoint = new IPEndPoint(IPAddress.Parse(interfaceIP), port);
                m_tcpListener = new TcpListener(ourEndPoint);
                m_tcpListener.Server.NoDelay = true;
                m_tcpListener.Start();
            }

            AcceptData data = new AcceptData(m_tcpListener, port, AcceptHandler, DisconnectHandler, messageHandler);
            m_tcpListener.BeginAcceptTcpClient(new AsyncCallback(FinishAccept), data);
        }

        private void FinishAccept(IAsyncResult result)
        {
            AcceptData data = (AcceptData)result.AsyncState;
            TcpClient tcpClient = null;

            try
            {
                tcpClient = data.tcpListener.EndAcceptTcpClient(result);
            }
            catch (ObjectDisposedException)
            {
                // Stop() was called
                return;
            }

            Debug.LogFormat("TCPServer: Accepted connection from {0}", tcpClient.Client.RemoteEndPoint);

            void DisconnectIntercepter(Session session, Exception e)
            {
                // Forward to user and remove from pending set
                data.DisconnectHandler(session, e);
                lock (m_lock)
                {
                    m_pendingSessions.Remove(session);
                }
            }

            // Create and start a new session
            Session session = new Session(tcpClient, DisconnectIntercepter, data.messageHandler);
            lock (m_lock)
            {
                m_pendingSessions.Add(session);
            }
            session.Start();
            data.AcceptHandler?.Invoke(session);

            // Continue listening for more connections
            m_tcpListener.BeginAcceptTcpClient(new AsyncCallback(FinishAccept), data);
        }
    }
}