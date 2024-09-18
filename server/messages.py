#
# messages.py
# Bart Trzynadlowski
#
# Messages passed between iOS client and Python server. Must be kept in sync with their iOS counter-
# parts.
#

from typing import List

from pydantic import BaseModel


class HelloMessage(BaseModel):
   message: str

class LogMessage(BaseModel):
    text: str

class DriveForDurationMessage(BaseModel):
    reverse: bool
    seconds: float
    speed: float

class DriveForDistanceMessage(BaseModel):
    reverse: bool
    meters: float
    speed: float

class RotateMessage(BaseModel):
    degrees: float

class DriveForwardMessage(BaseModel):
    deltaMeters: float

class WatchdogSettingsMessage(BaseModel):
    enabled: bool
    timeoutSeconds: float

class PWMSettingsMessage(BaseModel):
    pwmFrequency: int

class ThrottleMessage(BaseModel):
    maxThrottle: float

class PIDGainsMessage(BaseModel):
    whichPID: str
    Kp: float
    Ki: float
    Kd: float

class HoverboardRTTMeasurementMessage(BaseModel):
    numSamples: int
    delay: float
    rttSeconds: List[float]

class AngularVelocityMeasurementMessage(BaseModel):
    steering: float
    numSeconds: float
    angularVelocityResult: float

class PositionGoalToleranceMessage(BaseModel):
    positionGoalTolerance: float

class RenderSceneGeometryMessage(BaseModel):
    planes: bool
    meshes: bool

class RequestOccupancyMapMessage(BaseModel):
    unused: bool = False

class OccupancyMapMessage(BaseModel):
    cellsWide: int
    cellsDeep: int
    occupancy: List[float]
    robotCell: List[int]    # 2 elements: cellX, cellZ

class DrivePathMessage(BaseModel):
    pathCells: List[List[int]]  # list of [cellX, cellZ]

class RequestAnnotatedViewMessage(BaseModel):
    unused: bool = False

class AnnotatedViewMessage(BaseModel):
    imageBase64: str