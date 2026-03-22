using UnityEngine;

namespace ImmersiveTraining.StateHandling
{
    public class ActivatedByState : MonoBehaviour
    {
        /*  Component only used to tag objects that should only be activated or deactivated by StateData transitions
        These objects should be added to the specific ActivatedObjects list of the states for which they should be active or else they will remain deactivated.
        All objects with this tag component will be deactivated (or hidden if they also have the HideInsteadOfDeactivate tag component)
        whenever a new state is activated and it is not also in the activated object list.
        */
    }
}
