//
//  HumanInstancing.hpp
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/23/24.
//

#ifndef HumanInstancing_hpp
#define HumanInstancing_hpp

#include "BoxDepth.hpp"
#include <CoreVideo/CoreVideo.h>

extern std::vector<Box2D> findHumans(CVPixelBufferRef segmentationMap, uint8_t minimumConfidence);

#endif /* HumanInstancing_hpp */
