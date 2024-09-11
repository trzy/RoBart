//
//  FilterDepthMap.hpp
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/8/24.
//

#ifndef FilterDepthMap_hpp
#define FilterDepthMap_hpp

#include <CoreVideo/CoreVideo.h>

extern void filterDepthMap(CVPixelBufferRef depthMap, CVPixelBufferRef confidenceMap, uint8_t minimumConfidence);

#endif /* FilterDepthMap_hpp */
