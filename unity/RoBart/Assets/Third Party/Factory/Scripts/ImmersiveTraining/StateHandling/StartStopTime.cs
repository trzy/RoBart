using UnityEngine;
using UnityEngine.UI;

namespace ImmersiveTraining.StateHandling
{
    public class StartStopTime : MonoBehaviour
    {
        [SerializeField] private Image _buttonImage;
    
        [SerializeField] private Sprite _play;
        [SerializeField] private Sprite _pause;

        public bool _isTimeStopped;

        public void ToggleTimeOnOff()
        {
            _isTimeStopped = !_isTimeStopped;
        
            if (_isTimeStopped)
            {
                _buttonImage.sprite = _play;
                Time.timeScale = 0;
            }
            else
            {
                _buttonImage.sprite = _pause;
                Time.timeScale = 1;
            }
        }
    }
}
