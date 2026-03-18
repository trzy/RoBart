using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Threading;
using UnityEngine;



/// <summary>
/// Implementation of the Disruptor pattern
/// </summary>
/// <typeparam name="T">the type of item to be stored</typeparam>
public class BlockingRingBuffer<T>
{
    private readonly T[] _entries;
    // Data is added at _producerCursor and removed from _consumerCursor.  _producerCursor points to an empty node, so if
    // _producerCursor==_consumerCursor the list is empty. We lose one slot with this convention because if we wrap around
    // we'll still need to keep one free slot for _consumerCursor.
    private Volatile.PaddedLong _consumerCursor = new Volatile.PaddedLong();
    private Volatile.PaddedLong _producerCursor = new Volatile.PaddedLong();

    // https://msdn.microsoft.com/en-us/library/yy12yx1f.aspx
    private EventWaitHandle itemAddedEvent;
    private EventWaitHandle itemRemovedEvent;
    private EventWaitHandle stopWaitingEvent;
    private WaitHandle[] producerEventArray;
    private WaitHandle[] consumerEventArray;
    private bool m_overwiteConsumedWithDefault;

    /// <summary>
    /// Creates a new RingBuffer with the given capacity
    /// </summary>
    /// <param name="capacity">The capacity of the buffer</param>
    /// <param name="overwriteConsumedWithDefault">Overwrite dequeued elements in the ring buffer with default(T). Especially useful if passing memory buffers, to avoid holding onto memory references.</param>
    /// <remarks>Only a single thread may attempt to consume at any one time</remarks>
    public BlockingRingBuffer(int capacity, bool overwriteConsumedWithDefault)
    {
        capacity = NextPowerOfTwo(capacity);
        _entries = new T[capacity];

        itemAddedEvent = new AutoResetEvent(false);
        itemRemovedEvent = new AutoResetEvent(false);
        stopWaitingEvent = new ManualResetEvent(false);
        producerEventArray = new WaitHandle[2];
        producerEventArray[0] = itemRemovedEvent;
        producerEventArray[1] = stopWaitingEvent;
        consumerEventArray = new WaitHandle[2];
        consumerEventArray[0] = itemAddedEvent;
        consumerEventArray[1] = stopWaitingEvent;

        m_overwiteConsumedWithDefault = overwriteConsumedWithDefault;
    }

    public T this[long index]
    {
        get { unchecked { return _entries[index]; } }
        set { unchecked { _entries[index] = value; } }
    }

    /// <summary>
    /// The maximum number of items that can be stored
    /// </summary>
    public int Capacity
    {
        get { return _entries.Length; }
    }

    // Not tested extensively
    public int EstimateSize()
    {
        int consumer = _consumerCursor.ReadDoubleFence();
        int producer = _producerCursor.ReadDoubleFence();

        // Producer index is next to be filled (unoccupied). Consumer index is
        // next to pull (occupied).
        if (producer >= consumer)
        {
            return producer - consumer;
        }
        else
        {
            return producer + (Capacity - consumer);
        }
    }

    /// <summary>
    /// Removes an item from the buffer.
    /// </summary>
    /// <returns>The next available item</returns>
    public bool Dequeue(out T item)
    {
        var consumer = _consumerCursor.ReadDoubleFence();
        var consumerNext = (consumer + 1) % _entries.Length;

        while (consumer == _producerCursor.ReadDoubleFence())
        {
            consumerFlag = false;
            if (WaitHandle.WaitAny(consumerEventArray) == 1) // block until an item is added or "stopWaiting" is signaled
            {
                item = default(T);
                return false;
            }
        }
        item = this[consumer];
        if (m_overwiteConsumedWithDefault)
        {
            this[consumer] = default(T);
        }
        _consumerCursor.WriteFullFence(consumerNext);
        if (!producerFlag)
        {
            producerFlag = true;
            itemRemovedEvent.Set();
        }

        return true;
    }

    volatile bool producerFlag;
    volatile bool consumerFlag;

    /// <summary>
    /// Attempts to remove an items from the queue
    /// </summary>
    /// <param name="obj">the items</param>
    /// <returns>True if successful</returns>
    public bool TryDequeue(out T obj)
    {
        var consumer = _consumerCursor.ReadDoubleFence();

        if (consumer == _producerCursor.ReadDoubleFence())
        {
            obj = default(T);
            return false;
        }
        return Dequeue(out obj);
    }

    /// <summary>
    /// Add an item to the buffer
    /// </summary>
    /// <param name="item"></param>
    public bool Enqueue(T item)
    {
        var producer = _producerCursor.ReadFullFence();
        var producerNext = (producer + 1) % _entries.Length;

        while (producerNext == _consumerCursor.ReadFullFence())
        {
            producerFlag = false;
            if (WaitHandle.WaitAny(producerEventArray) == 1) // block until an item is removed or "stopWaiting" is signaled
                return false;
        }

        this[producer] = item;
        _producerCursor.WriteFullFence(producerNext);
        if (!consumerFlag)
        {
            consumerFlag = true;
            itemAddedEvent.Set();
        }

        return true;
    }

    /// <summary>
    /// Stops the producer/consumer who is blocked in enqueue()/dequeue() from waiting.
    /// </summary>
    /// <remarks>After this method is called, you should not call enqueue or dequeue again in this instance.
    public void StopWaiting()
    {
        stopWaitingEvent.Set();
        long la = _producerCursor.ReadDoubleFence();
        //Debug.Log(la);
    }

    /// <summary>
    /// The number of items in the buffer
    /// </summary>
    /// <remarks>for indicative purposes only, may contain stale data</remarks>
    public int Count { get { return (int)(_producerCursor.ReadDoubleFence() - _consumerCursor.ReadDoubleFence()); } }

    private static int NextPowerOfTwo(int x)
    {
        var result = 2;
        while (result < x)
        {
            result <<= 1;
        }
        return result;
    }


}

// http://preshing.com/20120913/acquire-and-release-semantics/
public static class Volatile
{
    private const int CacheLineSize = 64;

    [StructLayout(LayoutKind.Explicit, Size = CacheLineSize * 2)]
    public struct PaddedLong
    {
        [FieldOffset(CacheLineSize)]
        private int _value; // read and writes to ints are atomic

        /// <summary>
        /// Create a new <see cref="PaddedLong"/> with the given initial value.
        /// </summary>
        /// <param name="value">Initial value</param>
        public PaddedLong(int value)
        {
            _value = value;
        }

        /// <summary>
        /// Read the value without applying any fence
        /// </summary>
        /// <returns>The current value</returns>
        public int ReadUnfenced()
        {
            return _value;
        }

        /// <summary>
        /// Read the value applying full fence semantic
        /// </summary>
        /// <returns>The current value</returns>
        public int ReadDoubleFence()
        {
#if UNITY_EDITOR || !UNITY_WSA
            Thread.MemoryBarrier(); // needed to make sure the latest value is visible
#else
            Interlocked.MemoryBarrier();
#endif
            var value = _value;
#if UNITY_EDITOR || !UNITY_WSA
            Thread.MemoryBarrier(); // needed to make sure that the data are read after this
#else
            Interlocked.MemoryBarrier();
#endif
            return value;
        }

        /// <summary>
        /// Read the value applying full fence semantic
        /// </summary>
        /// <returns>The current value</returns>
        public int ReadFullFence()
        {
#if UNITY_EDITOR || !UNITY_WSA
            Thread.MemoryBarrier(); // needed to make sure the latest value is visible
#else
            Interlocked.MemoryBarrier();
#endif
            return _value;
        }

        /// <summary>
        /// Write the value applying full fence semantic
        /// </summary>
        /// <param name="newValue">The new value</param>
        public void WriteFullFence(int newValue)
        {
#if UNITY_EDITOR || !UNITY_WSA
            Thread.MemoryBarrier(); // needed to prevent making this write appear before the previous writes
#else
            Interlocked.MemoryBarrier();
#endif
            _value = newValue;
#if UNITY_EDITOR || !UNITY_WSA
            Thread.MemoryBarrier(); // needed to make sure that this change will be visible to other threads
#else
            Interlocked.MemoryBarrier();
#endif
        }
    }
}