# RoBart: Autonomous LLM-controlled robot using iPhone
*Copyright 2024 Bart Trzynadlowski*

**What if you could put your brain in a robot body?** Ok, ok, that's not possible, but what if you could put Claude or GPT-4 in a robot body? And not just any robot body but a robot body based on a salvaged hoverboard and an iPhone for compute and sensors? That's exactly what I did. Read on, human!

<p align="center"><img src="docs/Readme/Images/sealab.jpg" /></p>

<p align="center">
  <table>
    <tr>
      <td align="center"><img src="docs/Readme/Images/hide_and_seek_cover.jpg" /></td> <td align="center"><img src="docs/Readme/Images/hide_and_seek_cover.jpg" /></td>
    </tr>
    <tr>
      <td align="center">Hide and seek</td> <td align="center">Hide and seek</td>
    </tr>
  </table>
</p>

## Objectives

RoBart began as an attempt to build a cheap mobile base using a hoverboard and iPhone. Mobile phones are easy to work with and provide plenty of compute, connectivity, and useful peripherals: RGB cameras, LiDAR, microphones, speakers. Using [ARKit](https://developer.apple.com/augmented-reality/arkit/), we get SLAM, scene understanding, spatial meshing, and more. Let's see what we can do with this!

I'm open sourcing this project to stimulate discussion and encourage exploration. Some topics to consider:

- **Navigation:** RoBart needs better motion planning and navigation, particularly in household environments. An initial step would be to build a proper [nav mesh](https://en.wikipedia.org/wiki/Navigation_mesh) from its occupancy maps. Proper motion planning would be next.
- **Agent:** The agent could easily be improved with better planning, long-term memory, and spatial awareness. [Vision fine-tuning with GPT-4o](https://openai.com/index/introducing-vision-to-the-fine-tuning-api/) opens up all sorts of exciting possibilities.
- **Mechanical Design:** The mechanical design is a one-off. Can we design a simpler robot that's easier to replicate entirely from off-the-shelf and 3D-printed parts? Virtually nothing would need changing in the code.
- **Manipulation:** A RoBart Mk II should include an end effector, maybe something like this [5-dof Waveshare arm](https://www.waveshare.com/roarm-m1.htm) or the [SO-ARM100](https://github.com/TheRobotStudio/SO-ARM100).
- **Applications:** Accessibility? Tidying-up? Contactless health? Home inspection and security? A robotic porter? What are some fun ideas that could be built?

If you have ideas or contributions, I encourage you to reach out!

## System Architecture

RoBart is a bit of a fever dream of ideas, many only partly finished. I'll attempt to describe how the code base works here.

### High-Level Overview

The RoBart code base contains four distinct applications, only two of which constitute the robot:

1. **iOS application:** This is the main RoBart app that runs on iPhone and controls RoBart. It does not rely on a companion server and makes calls to public LLM APIs directly. The app actually has two modes: robot and handheld, the latter localizing itself to the same SLAM map and allowing for remote control. Located at `ios/RoBart/`.
2. **Arduino firmware:** Firmware that runs on the [Adafruit Feather nRF52 Bluefruit LE](https://www.adafruit.com/product/3406?g=&gad_source=1&gclid=CjwKCAiA3ZC6BhBaEiwAeqfvykMG2eNFgYPQH7afzyBHNYS5us6RZF8WMFso22wj9rWsmRq58V3ItRoC2-QQAvD_BwE) to control the motors. Communicates with the iOS app via Bluetooth Low Energy. Located at `hoverboard/`.
3. **watchOS application:** An optional Apple Watch app that allows voice commands to be issued from Watch. This is useful in noisy environments that confound the VAD running on the iPhone. Located at `ios/RoBart/` as a watchOS build target.
4. **Debug server:** A Python-based server that the iOS app will attempt to connect to. Provides an interactive terminal that allows various debug commands to be issued, both to control the robot and request data from it. This is not required to operate the robot. Located at `server/`.

The main components of the RoBart iOS app are shown in the diagram below.

<p align="center">
  <table>
    <tr>
      <td align="center"><img src="docs/Readme/Images/system_diagram.png" /></td>
    </tr>
    <tr>
      <td align="center">RoBart iOS app architecture.</td>
    </tr>
  </table>
</p>

The components are:

- **ARSessionManager:** Using ARKit, publishes camera transform and frame updates, performs scene meshing and floor plane detection, and even supports collaborative sessions with other phones running the app in handheld mode. RoBart components frequently poll the current camera transform or wait for the next frame.
- **SpeechDetector:** Listens for spoken audio, transcribes it using Deepgram, and then publishes the resulting transcript. An external transcription API is used because iOS's `SFSpeechRecognizer` is performance intensive.
- **AudioManager:** Plays audio samples (i.e., RoBart's spoken utterances) and controls the microphone (used by `SpeechDetector`).
- **HoverboardController:** Executes trajectories (e.g., rotate N degrees, drive forward N meters) using PID control on iOS and by sending motor throttle commands to the hoverboard Arduino firmware via BLE.
- **NavigationController:** Higher-level motion control and navigation. Builds an occupancy map, performs very crude pathfinding, provides a nearest-human following task, and executes motion tasks using `HoverboardController`.
- **AnnotatingCamera:** Takes photos and annotates them with navigable points (using the occupancy map). This allows the AI agent to reason about where it can move.
- **Brain:** The AI agent that runs RoBart. Listens for speech and will then attempt to complete the requested task using all of RoBart's capabilities and the chosen LLM.

### Motor Control

`HoverboardController` communicates with the Arduino firmware via BLE. It sends individual motor throttle values (ranging from -1.0 to +1.0, with sign indicating direction) directly. A number of basic trajectory commands are handled on iOS by employing a PID controller that uses ARKit's 6dof pose for feedback (yes, running a PID loop like this through BLE and with ARKit's latency is engineering malpractice but it almost works). These include:

- **drive:** Sets the individual throttle values for the left and right motors, open loop.
- **rotateInPlace:** Turns in place with the given angular velocity (-1 being left at full throttle and +1 being right at full throttle), open loop.
- **rotateInPlaceBy:** Rotates in place by a specified number of degrees.
- **face:** Turns in place to face the given world space direction vector.
- **driveForward:** Drive forward by the specified distance in meters.
- **driveTo:** Drives to the specified world space position in a straight line, both turning to face the point and moving towards it.
- **driveToFacing:** Drives to the specified position while facing the given direction. Particularly useful for driving backwards to a point.

There is currently no feedback on the Arduino side. No encoder is present on the motors. A watchdog mechanism exists that will cut motor power when either the BLE connection is lost or if motor throttle values are not updated within a certain number of seconds. In the PID controlled modes, a stream of constant updates is sent, which prevents the watchdog from engaging. 

### Position Tracking and Mapping with ARKit

### Photo Input

### Voice Input

### Agent Loop

## Mechanical and Electrical Design

