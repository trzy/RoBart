using ImmersiveTraining.Management;
using UnityEngine;
using UnityEngine.UI;

namespace DistributionCenter
{
    public class CameraSwitcher : MonoBehaviour
    {
        public GameObject[] cameras;
        public Button[] switchButtons;
        public GameObject subMenu;
        public GameObject trainingSubMenu;
        public GameObject[] Light_ARR;

        private static int currentCameraIndex = 0;

        void Start()
        {
            for (int i = 0; i < switchButtons.Length; i++)
            {
                int index = i;
                switchButtons[i].onClick.AddListener(() => SwitchCamera(index));
            }

            if (subMenu != null)
                subMenu.SetActive(false);
        
            if (trainingSubMenu != null)
                trainingSubMenu.SetActive(true);

            SwitchCamera(0);
        }

        void SwitchCamera(int index)
        {
            if (index >= 0 && index < cameras.Length)
            {
                bool turnOffLights = index == 0 || index == 2 || index == 3;
                if (Light_ARR != null)
                {
                    foreach (GameObject lightObj in Light_ARR)
                    {
                        lightObj.SetActive(!turnOffLights);
                    }
                }

                for (int i = 0; i < cameras.Length; i++)
                {
                    cameras[i].SetActive(i == index);
                    switchButtons[i].GetComponent<Image>().color = (i == index) ? Color.black : Color.white;
                }

                if (subMenu != null)
                    subMenu.SetActive(index == 1);
            
                if (trainingSubMenu != null)
                    trainingSubMenu.SetActive(index == 0);

                // This resets the timer for the step when you come back to this camera angle
                if (index == 0 && index != currentCameraIndex)
                    EventManager.TriggerEvent(EventTypes.RESET_TIMER, gameObject);
                else
                    EventManager.TriggerEvent(EventTypes.STOP_TIMER, gameObject);

                currentCameraIndex = index;
            }
        }
    }
}
