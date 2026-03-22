using ImmersiveTraining.Management;
using TMPro;
using UnityEngine;

namespace ImmersiveTraining.StateHandling
{
    public class UI_StateTracker : MonoBehaviour
    {
        [SerializeField] private StateManager _stateManager;
        [SerializeField] private TMP_Text _stateTrackerText;

        public void Start()
        {
            EventManager.StartListening(EventTypes.STATE_CHANGED, UpdateStateTrackerUIText);
        
            UpdateStateTrackerUIText(this.gameObject);
        }

        private void UpdateStateTrackerUIText(GameObject invoker)
        {
            _stateTrackerText.text = _stateManager.GetStateTrackerText();
        }
    }
}
