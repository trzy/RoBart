using UnityEngine;
using UnityEngine.UI;

namespace DistributionCenter
{
    public class GPUDetection : MonoBehaviour
    {
        public Text GPU_Info;
        public Text GPU_Type;

        private readonly string[] allowedGPUNumbers = new string[]
        {
            "5090", "5080", "5070", "5060", "5050",
            "4090", "4080", "4070", "4060", "4050",
            "3090", "3080", "3070", "3060", "3050",
            "2080", "2070", "2060", "2050"
        };

        void Start()
        {
            SetGPUInfo();
        }

        void SetGPUInfo()
        {
            string gpuName = SystemInfo.graphicsDeviceName;
            string filteredGPUInfo = GetFilteredGPUName(gpuName);
            string displayText = string.IsNullOrEmpty(filteredGPUInfo) ? "unknown gpu" : filteredGPUInfo.ToLower();

            if (GPU_Info != null)
            {
                GPU_Info.text = displayText;
                GPU_Info.fontSize = displayText == "unknown gpu" ? 40 : GPU_Info.fontSize;
            }

            if (GPU_Type != null)
            {
                string lowerGPU = gpuName.ToLower();
                string typeText;

                if (lowerGPU.Contains("nvidia"))
                    typeText = "nvidia";
                else if (lowerGPU.Contains("radeon"))
                    typeText = "radeon";
                else
                    typeText = "unknown gpu type";

                GPU_Type.text = typeText;
                GPU_Type.fontSize = typeText == "unknown gpu type" ? 40 : GPU_Type.fontSize;
            }
        }

        string GetFilteredGPUName(string gpuName)
        {
            foreach (string gpuNumber in allowedGPUNumbers)
            {
                if (gpuName.Contains(gpuNumber))
                    return gpuNumber;
            }
            return null;
        }
    }
}