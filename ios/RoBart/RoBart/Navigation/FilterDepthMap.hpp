//
//  FilterDepthMap.hpp
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/8/24.
//

#ifndef FilterDepthMap_hpp
#define FilterDepthMap_hpp

#include <CoreVideo/CoreVideo.h>

extern void filterDepthMap(CVPixelBufferRef depth_map, CVPixelBufferRef confidence_map, uint8_t minimum_confidence);

#endif /* FilterDepthMap_hpp */
