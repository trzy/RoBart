using System;
using System.Collections.Generic;
using ImmersiveTraining.Management;
using TMPro;
using UnityEngine;

namespace ImmersiveTraining.TrainingInteractions
{
    public class TrainingCompleteHandler : MonoBehaviour
    {
        [SerializeField] private Material _instructionScreen;
        [SerializeField] private Texture _finalInstrunctionImage;
    
        [SerializeField] private GameObject _assemblyCompletePanel;
        [SerializeField] private TMP_Text _finalTimeText;
        [SerializeField] private List<TMP_Text> _stepTimeTextList;

        private TimeManager _timeManager;

        void Start()
        {
            EventManager.StartListening(EventTypes.TRAINING_COMPLETE, SetSceneForCompletedTraining);
            EventManager.StartListening(EventTypes.FINAL_TIMES_SAVED, UpdateUIWithFinalTimes);
        }
    
        private void SetSceneForCompletedTraining(GameObject arg0)
        {
            _instructionScreen.mainTexture = _finalInstrunctionImage;
            _assemblyCompletePanel.SetActive(true);
        }
    
        private void UpdateUIWithFinalTimes(GameObject callingTimeManagerObject)
        {
            _timeManager = callingTimeManagerObject.GetComponent<TimeManager>();

            if (_timeManager != null)
            {
                int totalTime = _timeManager.GetTotalTime();
                _finalTimeText.text = $"You finished the assembly in: {totalTime} seconds!";

                List<TimeData> timeDataList = _timeManager.StepTimeLog;

            
                for (int i = 0; i < _stepTimeTextList.Count; i++)
                {
                    TimeData currentTimeData = timeDataList[i + 1]; //start at 1 to skip the total time entry at 0
                    _stepTimeTextList[i].text = currentTimeData.StepName.Substring(currentTimeData.StepName.IndexOf("Step", StringComparison.Ordinal)) + " : " + currentTimeData.TimeInSeconds + " seconds";
                }
            }
        }
    }
}
