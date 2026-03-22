// Tag a state with this interface to mark as a timed step and trun on the timer in the UI
namespace ImmersiveTraining.StateHandling
{
    public interface IUseTimer
    {
        public bool CountsDown { get; }
        public int TimeAllowedInSeconds { get; set; }
    }
}
