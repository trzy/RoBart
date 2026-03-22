using UnityEngine;
using UnityEngine.UI;

namespace DistributionCenter
{
    public class UI_Toggle : MonoBehaviour
    {
        public GameObject[] objectsToToggle;
        public Button toggleButton;

        public bool startEnabled;
        private bool isEnabled = false;

        void Start()
        {
            isEnabled = startEnabled;

            if (objectsToToggle != null)
            {
                foreach (var obj in objectsToToggle)
                    if (obj != null)
                        obj.SetActive(isEnabled);
            }

            if (toggleButton != null)
                toggleButton.onClick.AddListener(ToggleObjects);
        }

        public void ToggleObjects()
        {
            isEnabled = !isEnabled;

            foreach (var obj in objectsToToggle)
                if (obj != null)
                    obj.SetActive(isEnabled);
        }
    }
}