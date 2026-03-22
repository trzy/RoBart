using System.Collections.Generic;
using ImmersiveTraining.Management;
using UnityEngine;
using UnityEngine.InputSystem;

namespace ImmersiveTraining.TrainingInteractions
{
    public class HighlightManager : MonoBehaviour
    {
        public Material outlineMaterial;
        public LayerMask highlightableLayer;
        public string outlineLayerName;
        public string highlightProperty = "_On_Select";
        public string colorProperty = "_HighlightColor";

        public Color defaultOutlineColor;
        public Color rightColor = Color.green; // Color for "correct" state
        public Color wrongColor = Color.red;   // Color for "incorrect" state

        private GameObject currentHighlightedObject;
        private Dictionary<Renderer, Material[]> originalMaterialsMap = new Dictionary<Renderer, Material[]>();
        private List<Renderer> currentRenderers = new List<Renderer>();
        private StateManager_Training _stateManager_Training;
        private static readonly int OutlineColor = Shader.PropertyToID("_OutlineColor");

        private void Start()
        {
            _stateManager_Training = FindFirstObjectByType<StateManager_Training>();
        }

        void Update()
        {
            if (TrainingTypeManager.Instance.IsTrainingMode)
            {
                HandleMouseOverHighlight();
            
                if (Mouse.current.leftButton.isPressed)
                {
                    if (currentHighlightedObject != null)
                    {
                        SetHighlightColor(CheckRightOrWrong());
                    }
                }
            }
            else
            {
                if (Mouse.current.leftButton.wasReleasedThisFrame)
                {
                    HandleMouseOverHighlight();
                
                    SetHighlightColor(CheckRightOrWrong());
                }
            }
        }

        private void HandleMouseOverHighlight()
        {
            Vector2 mousePosition = Mouse.current.position.value;
            Ray ray = Camera.main.ScreenPointToRay(new Vector3(mousePosition.x, mousePosition.y, 0));
            if (Physics.Raycast(ray, out RaycastHit hit, Mathf.Infinity, highlightableLayer))
            {
                GameObject hitObject = hit.collider.gameObject;
            
                if (hitObject != currentHighlightedObject)
                {
                    if (currentHighlightedObject != null)
                    {
                        RemoveHighlight(currentHighlightedObject);
                    }
                
                    currentHighlightedObject = hitObject;
                    ApplyHighlight(currentHighlightedObject);
                }
            }
            else
            {
                // If no object is hit, remove highlight from the current object
                if (currentHighlightedObject != null)
                {
                    RemoveHighlight(currentHighlightedObject);
                    currentHighlightedObject = null;
                }
            }
        }

        private void ApplyHighlight(GameObject target)
        {
            currentRenderers.Clear();
            target.GetComponentsInChildren<Renderer>(currentRenderers);

            foreach (var renderer in currentRenderers)
            {
                /*if (!originalMaterialsMap.ContainsKey(renderer))
            {
                originalMaterialsMap[renderer] = renderer.sharedMaterials;
            }
            
            Material[] newMaterials = renderer.materials;
            for (int i = 0; i < newMaterials.Length; i++)
            {
                if (newMaterials[i].HasProperty(highlightProperty))
                {
                    newMaterials[i] = new Material(newMaterials[i]); // Create a copy
                    newMaterials[i].SetFloat(highlightProperty, 1f);
                }
            }

            renderer.materials = newMaterials;*/

                renderer.gameObject.layer = LayerMask.NameToLayer(outlineLayerName);
            }
        }

        private void RemoveHighlight(GameObject target)
        {
        
            target.GetComponentsInChildren<Renderer>(currentRenderers);

            foreach (var renderer in currentRenderers)
            {
                /*if (originalMaterialsMap.TryGetValue(renderer, out Material[] originalMaterials))
            {
                renderer.materials = originalMaterials; // Restore original shared materials
            }*/

                renderer.gameObject.layer = LayerMask.NameToLayer("Default");
                outlineMaterial.SetColor(OutlineColor, defaultOutlineColor);
            }
        
            currentRenderers.Clear();
        }

        private void SetHighlightColor(bool isCorrect)
        {
            foreach (var renderer in currentRenderers)
            {
                Material[] materials = renderer.materials;
                foreach (var material in materials)
                {
                    if (material.HasProperty(colorProperty)) // Check if the shader has the color property
                    {
                        material.SetColor(colorProperty, isCorrect ? rightColor : wrongColor);
                    }
                }

                renderer.materials = materials;
            }
        
            if (outlineMaterial.HasProperty(OutlineColor))
                outlineMaterial.SetColor(OutlineColor, (isCorrect) ? rightColor : wrongColor);
        }

        private bool CheckRightOrWrong()
        {
            return (currentHighlightedObject == _stateManager_Training.GetCurrentTrainingPartToMove());
        }
    }
}