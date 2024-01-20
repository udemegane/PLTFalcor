#pragma once

// #include "pltpt.slangh"
#include "Scene/SceneDefines.slangh"
#include "Utils/Math/MathConstants.slangh"
import Scene.Scene;
import Scene.HitInfo;
import Scene.HitInfoType;
import Scene.RaytracingInline;
import Utils.Sampling.SampleGenerator;

import LocalUtils;


// Inputs
RWTexture2D<float4> gIndirectIllumination;

// Outputs
RWTexture2D<float4> gOutputColor;

cbuffer CB
{
    uint gFrameCount; // Frame count since scene was loaded.

    uint2 kOutputSize;

#if DO_DEBUG_VIEW == 1
    float kDebugViewIntensity;
#endif
}


[numthreads(16, 16, 1)]
void main(
    uint3 groupId: SV_GroupID,
    uint3 groupThreadId: SV_GroupThreadID,
    uint3 dispatchThreadId: SV_DispatchThreadID,
    uint3 groupIndex: SV_GroupIndex
)
{
    uint2 pixel = dispatchThreadId.xy;
    if (any(pixel >= kOutputSize.xy))
        return;
    float a;
    // SampleGenerator sg = SampleGenerator(pixel, gFrameCount * gFrameCount);
    gOutputColor[pixel] += gIndirectIllumination[pixel];

}
