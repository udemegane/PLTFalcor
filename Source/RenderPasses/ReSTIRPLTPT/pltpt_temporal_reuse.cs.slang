#pragma once

#include "pltpt_cs.slangh"

import LocalUtils;

RWStructuredBuffer<PackedReservoir> gPrevReservoirs;
RWStructuredBuffer<PackedReservoir> gCurrReservoirs;

StructuredBuffer<BounceData> bounceBuffer;
StructuredBuffer<BounceData> retracedBounceBuffer;
// Read a bounce

RWTexture2D<float4> gIndirectIllumination;

BounceData readBounce(int p, const uint2 pixel, const bool retraced = false)
{
    const uint idx = ((pixel.x % mTileSize) + (pixel.y % mTileSize) * mTileSize) * (mMaxBounces + 1) + p;
    if (retraced)
        return retracedBounceBuffer[idx];
    else
        return bounceBuffer[idx];
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
    // gOutputColor[pixel] += gIndirectIllumination[pixel];

}
