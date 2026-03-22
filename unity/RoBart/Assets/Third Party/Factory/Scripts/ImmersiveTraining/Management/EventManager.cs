using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Events;

namespace ImmersiveTraining.Management
{
    public class UnityObjectEvent : UnityEvent<GameObject> { }

    public enum EventTypes
    {
        STATE_CHANGED = 0,
        CHANGED_TO_FPS = 1,
        CHANGED_TO_FIXED_CAMERA = 2,
        FIXED_CAMERA_VIEWPOINT_CHANGED = 3,
        CAMERA_STARTED_LERP = 4,
        CAMERA_FINISHED_LERP = 5,
        CHANGED_TO_FREE_CAMERA = 6,
        ON_SENSOR_ICON_CLICK = 7,
        STATE_ACTIVATION_EVENT = 8,
        STATE_DEACTIVATION_EVENT =9,
        POP_MODAL_PANEL_WITH_MESSAGE_ON_OBJECT =10,
        NETWORK_AVATAR_SPAWNED = 11,
        NETWORK_AVATAR_DESPAWNED = 12,
        SESSION_CLOSED_BY_HOST = 13,
        CLIENT_MANUALLY_DISCONNECTED = 14,
        TRAINING_STATE_CRITERIA_REACHED = 15,
        TRAINING_STATE_FAILED = 16,
        START_TIMER = 17,
        STOP_TIMER = 18,
        TRAINING_COMPLETE = 19,
        AUTOPLAY_STATE_DEMONSTRATION = 20,
        TRAINING_STATE_COMPLETION_CHECK = 21,
        RESET_TIMER = 22,
        ALLOWED_TIME_EXPIRED = 23,
        RESET_TRAINING = 24,
        FINAL_TIMES_SAVED
    }


    public class EventManager : Singleton<EventManager>
    {
        private Dictionary<EventTypes, UnityObjectEvent> objectEventDictionary;
        private static EventManager eventManager;

        private void Awake()
        {
            Initialize();
        }

        public void Initialize()
        {
            if (objectEventDictionary == null)
            {
                objectEventDictionary = new Dictionary<EventTypes, UnityObjectEvent>();
            }
        }

        public static void StartListening(EventTypes eventType, UnityAction<GameObject> listener)
        {
            UnityObjectEvent thisEvent = null;
            if (Instance.objectEventDictionary.TryGetValue(eventType, out thisEvent))
            {
                thisEvent.AddListener(listener);
            }
            else
            {
                thisEvent = new UnityObjectEvent();
                thisEvent.AddListener(listener);
                Instance.objectEventDictionary.Add(eventType, thisEvent);
            }
        }

        public static void StopListening(EventTypes e, UnityAction<GameObject> listener)
        {
            UnityObjectEvent thisEvent = null;
            if (Instance.objectEventDictionary.TryGetValue(e, out thisEvent))
            {
                thisEvent.RemoveListener(listener);
            }
        }

        public static void TriggerEvent(EventTypes e, GameObject invoker)
        {
            UnityObjectEvent thisEvent = null;
            if (Instance.objectEventDictionary.TryGetValue(e, out thisEvent))
            {
                thisEvent.Invoke(invoker);
            }
        }
    }
}