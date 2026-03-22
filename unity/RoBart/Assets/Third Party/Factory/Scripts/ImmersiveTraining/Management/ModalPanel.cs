using TMPro;
using UnityEngine;

namespace ImmersiveTraining.Management
{
    public class ModalPanel : Singleton<ModalPanel>
    {
        [SerializeField] private GameObject _modalPanel;
        [SerializeField] private TextMeshProUGUI _panelText;
        [SerializeField] private Animator _animator;
        private static readonly int PlayNotification = Animator.StringToHash("PlayNotification");

        void Start()
        {
            _modalPanel.SetActive(false);
        
            EventManager.StartListening(EventTypes.POP_MODAL_PANEL_WITH_MESSAGE_ON_OBJECT, PopModalPanelWithMessageFromObject);
        }

        public void ClosePanel()
        {
            // This resets the timer for the current state/step when you close the panel that says the last step is completed
            EventManager.TriggerEvent(EventTypes.RESET_TIMER, _modalPanel);
            _modalPanel.SetActive(false);
        }

        //This method requires that the calling object implements the IMessageForModal interface
        private void PopModalPanelWithMessageFromObject(GameObject callingObject)
        {
            _panelText.text = callingObject.GetComponent<IMessageForModalPanel>()?.MessageForModal();
            _modalPanel.SetActive(true);
            _animator.SetTrigger(PlayNotification);
        }
    }
}
