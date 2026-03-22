using System;
using System.Collections.Generic;
using ImmersiveTraining.StateHandling;
using TMPro;
using UnityEngine;

namespace ImmersiveTraining.Management
{
    public class TimeManager : MonoBehaviour
    {
        [SerializeField]
        TMP_Text timeField;
        [SerializeField]
        StateManager stateManager;
        [SerializeField]
        int secondsWhenWarningStarts = 30;
        [SerializeField]
        string jsonFileName = "TimeDataLog.json";

        float timer;
        float totalTime;
        string formattedTime;
        bool timeStarted;
        bool countDown;
        bool timeExpiredNotified;
        int secondsAllowedForStep;
        Color initialTimeColor;
        StateData currentStep;
        List<TimeData> stepTimeLog;
        TimeData totalTimeData;
        public List<TimeData> StepTimeLog { get => stepTimeLog; }

        void OnEnable()
        {
            if (stateManager == null)
            {
                stateManager = FindFirstObjectByType<StateManager>();
            }
        }

        void OnDisable()
        {
            // Write log to console just to see it
            if (totalTime > 0)
            {
                // We have not saved it to file yet
                StatesStopped(gameObject);
            }
            WriteTimeLogToConsole(jsonFileName);
        }

        void Start()
        {
            initialTimeColor = timeField != null ? timeField.color : Color.white;
            ResetTimeLog();
            EventManager.StartListening(EventTypes.START_TIMER, StateStarted);
            EventManager.StartListening(EventTypes.STOP_TIMER, StateEnded);
            EventManager.StartListening(EventTypes.RESET_TIMER, StateRestarted);
            EventManager.StartListening(EventTypes.TRAINING_COMPLETE, AllStatesCompleted);
            EventManager.StartListening(EventTypes.SESSION_CLOSED_BY_HOST, StatesStopped);
            EventManager.StartListening(EventTypes.CLIENT_MANUALLY_DISCONNECTED, StatesStopped);
        }

        void Update()
        {
            if (timeStarted)
            {
                timer += Time.deltaTime;
                DisplayTime();
            }
        }

        void StateStarted(GameObject callingObject)
        {
            ResetStepTime();
            CountdownCheck(callingObject);
            timeStarted = true;
        }

        void StateEnded(GameObject callingObject)
        {
            timeStarted = false;
            LogTotalTime();
        }

        void StateRestarted(GameObject callingObject)
        {
            var trainingManager = callingObject?.GetComponent<TrainingTypeManager>();
            if (trainingManager)
            {
                if (trainingManager.IsTrainingMode != countDown)
                    return;

                LogTotalTime();
                ResetStepTime();
                CountdownCheck(currentStep.gameObject);
                return;
            }

            var stateGameObject = stateManager.CurrentState.gameObject;
            StateStarted(stateGameObject);
        }

        void StatesStopped(GameObject callingObject)
        {
            var timeDataLog = new TimeDataCollection { TimeDataLog = new List<TimeData>(stepTimeLog) };
            JsonFileUtility.WriteJsonToFile(timeDataLog, jsonFileName);
            ResetTimeLog();
        }

        void AllStatesCompleted(GameObject callingObject)
        {
            var timeDataLog = new TimeDataCollection { TimeDataLog = new List<TimeData>(stepTimeLog) };
            var stampedFilename = System.IO.Path.GetFileNameWithoutExtension(jsonFileName) + DateTime.Now.ToString("yyyyMMddHHmmss") + ".json";
            JsonFileUtility.WriteJsonToFile(timeDataLog, stampedFilename);
        
            //Notify of final data being stored before resetting the log
            EventManager.TriggerEvent(EventTypes.FINAL_TIMES_SAVED, gameObject);
        
            ResetTimeLog();
        }

        void CountdownCheck(GameObject callingObject)
        {
            var stateData = callingObject.GetComponent<StateData>();
            if (stateData != null)
            {
                var timerUsed = stateData as IUseTimer;
                if (timerUsed != null)
                {
                    countDown = timerUsed.CountsDown;
                    if (countDown)
                    {
                        secondsAllowedForStep = timerUsed.TimeAllowedInSeconds;
                    }
                    if (timeField != null)
                    {
                        timeField.gameObject.SetActive(countDown);
                    }
                }
            }
        }

        void ResetStepTime()
        {
            timer = 0f;
            formattedTime = string.Empty;
            secondsAllowedForStep = 0;
            countDown = false;
            timeExpiredNotified = false;
            currentStep = stateManager.CurrentState;
        }

        void ResetTimeLog()
        {
            timeStarted = false;
            stepTimeLog = new List<TimeData>();
            totalTime = 0f;
            AddTotalTime();
        }

        void DisplayTime()
        {
            if (countDown)
            {
                var timeLeft = secondsAllowedForStep + 1 - timer;
                if (timeLeft < 0f)
                {
                    timeLeft = 0f;
                    if (!timeExpiredNotified)
                        NotifyTimeExpired();
                }
                formattedTime = FormatTime(timeLeft, false);

                if (timeField != null)
                {
                    timeField.text = formattedTime;
                    timeField.color = (countDown && (secondsAllowedForStep - timer) < secondsWhenWarningStarts) ? Color.red : initialTimeColor;
                }
            }
        }

        void NotifyTimeExpired()
        {
            EventManager.TriggerEvent(EventTypes.ALLOWED_TIME_EXPIRED, currentStep.gameObject);
            timeExpiredNotified = true;
            Debug.Log("Time ran out.");
        }

        string FormatTime(float _time, bool round)
        {
            int minutes = Mathf.FloorToInt(_time / 60f);
            int seconds = round ? Mathf.RoundToInt(_time - minutes * 60) : Mathf.FloorToInt(_time - minutes * 60);
            if (minutes > 59)
            {
                int hours = Mathf.FloorToInt(minutes / 60f);
                minutes = minutes - hours * 60;
                return string.Format("{0:0}:{1:00}:{2:00}", hours, minutes, seconds);
            }
            else
                return string.Format("{0:0}:{1:00}", minutes, seconds);
        }

        void LogTotalTime()
        {
            // Add the step to the log
            var thisStepTime = new TimeData(currentStep.StateName, Mathf.RoundToInt(timer), FormatTime(timer, true), !countDown);
            Debug.LogFormat("Time taken for step {0} is {1}", currentStep.StateName, FormatTime(timer, true));
            AddTimeToLogList(thisStepTime);
            totalTime += timer;
            AddTotalTime();
        }

        void AddTotalTime()
        {
            totalTimeData = new TimeData("Total Time", Mathf.RoundToInt(totalTime), FormatTime(totalTime, true), !countDown);
            AddTimeToLogList(totalTimeData);
        }

        void AddTimeToLogList(TimeData stepData)
        {
            if (stepData.StepName == "Total Time")
            {
                int index = stepTimeLog.FindIndex(s => s.StepName == "Total Time");
                if (index != -1)
                {
                    stepTimeLog[index] = stepData;
                    return;
                }
            }

            stepTimeLog.Add(stepData);
            Debug.Log(stepTimeLog.Count);
        }

        void WriteTimeLogToConsole(string filePath)
        {
            var newLog = JsonFileUtility.ReadJsonFromFile<TimeDataCollection>(filePath);
            if (newLog != null)
            {
                foreach (var step in newLog.TimeDataLog)
                {
                    Debug.LogFormat("Step: {0}  Time in seconds: {1}   Formatted time: {2}   In training mode: {3}", 
                        step.StepName, step.TimeInSeconds, step.FormattedTime, step.InTrainingMode);
                }
            }
        }

        public int GetTotalTime()
        {
            return totalTimeData.TimeInSeconds;
        }
    
    
    }

    [Serializable]
    public class TimeData
    {
        public string StepName;
        public int TimeInSeconds;
        public string FormattedTime;
        public bool InTrainingMode;

        public TimeData(string stepName, int time, string formattedTime, bool inTrainingMode)
        {
            StepName = stepName;
            TimeInSeconds = time;
            FormattedTime = formattedTime;
            InTrainingMode = inTrainingMode;
        }
    }

    [Serializable]
    public class TimeDataCollection
    {
        public List<TimeData> TimeDataLog = new();
    }
}