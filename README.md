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

### High-Level Overview

### Motor Control

### Position Tracking and Mapping with ARKit

### Photo Input

### Voice Input

### Agent Loop

## Mechanical and Electrical Design

