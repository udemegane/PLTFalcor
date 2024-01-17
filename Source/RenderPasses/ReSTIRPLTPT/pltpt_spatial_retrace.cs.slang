#pragma once

#include "Scene/SceneDefines.slangh"
#include "Utils/Math/MathConstants.slangh"

#include "pltpt_constants.slangh"
#include "pltpt_debug.slangh"

#include "DebugViewType.slangh"

#include "ShadowRays.slangh"
#include "Manifolds.slangh"

import Scene.Raytracing;
import Scene.Intersection;
import Scene.ShadingData;
import Scene.Scene;

import Utils.HWSS;
import Utils.Math.MathHelpers;
import Utils.Sampling.SampleGenerator;
import Utils.Geometry.GeometryHelpers;
import Utils.Color.SpectrumSampler;
import Utils.Color.SpectrumUtils;

import Utils;
import Path;
import PathHelper;
import Reservoir;
import Rendering.PLT;

import Rendering.Lights.LightHelpers;
import Rendering.Lights.EmissiveLightSampler;
import Rendering.Lights.EmissiveLightSamplerHelpers;
import Rendering.Lights.EnvMapSampler;

import Rendering.Materials.BxDF;
import Rendering.Materials.PLT.Mueller;

import Rendering.Utils.LightsSamplingUtils;

import ColourCoding;

// TODO: replace it
static const uint kMaxNeighbours = 8;
static const uint kSampleRadius = 10;

cbuffer CB
{
    uint gFrameCount; // Frame count since scene was loaded.
    uint2 gFrameDim; // Frame dimensions.
    EnvMapSampler envMapSampler;
    EmissiveLightSampler emissiveSampler;

    uint2 kOutputSize;
    uint2 kTile;

    // Area on emissive geometry from which we source beams
    float kSourcingAreaFromEmissiveGeometry;
    // Max diffusivity of sourced beams
    float kSourcingMaxBeamOmega;

#if DO_DEBUG_VIEW == 1
    float kDebugViewIntensity;
#endif
}

// Inputs
StructuredBuffer<BounceData> gBounceBuffer;
StructuredBuffer<PackedReservoir> gInputReservoirs;

// Outputs
RWStructuredBuffer<BounceData> gRetracedBounceBuffer;
RWStructuredBuffer<PackedReservoir> gOutputReservoirs;

//////////////////////////////////////////////////////////////////////////
// Constants
static const uint mMaxBounces = MAX_BOUNCES;
static const uint mTileSize = TILE_SIZE;

static const bool mHWSSDoMIS = HWSS_MIS;

static const uint kDebugViewType = DEBUG_VIEW_TYPE;

static const bool kUseDirectLights = USE_DIRECT_LIGHTS;
static const bool kUseEmissiveLights = USE_EMISSIVE_LIGHTS;
static const bool kUseEnvLight = USE_ENV_LIGHT;
static const bool kUseAnalyticLights = USE_ANALYTIC_LIGHTS;

static const bool kAlphaMasking = ALPHA_MASKING;

static const bool kImportanceSampleEmissiveSpectra = DO_IMPORTANCE_SAMPLING_EMITTERS;

static const bool kDoNEE = DO_NEE;
static const bool kDoMSonNEE = kDoNEE && DO_MNEE;
static const bool kDoMIS = kDoNEE && DO_MIS;

static const bool kNEEUsePerTileSelectorSG = kDoNEE && NEE_USE_PER_TILE_SG_SELECTOR;

static const bool kDoRussianRoulette = DO_RUSSIAN_ROULETTE;

static const bool kForceFullyCoherent = false;

//////////////////////////////////////////////////////////////////////////

// Read a bounce
BounceData readBounce(int p, const uint2 pixel)
{
    const uint idx = ((pixel.x % mTileSize) + (pixel.y % mTileSize) * mTileSize) * (mMaxBounces + 1) + p;
    return gBounceBuffer[idx];
}

// Read/Write a reservoir
Reservoir readReservoir(const uint2 pixel)
{
    const uint idx = encodeMortonCode(pixel);
    return gInputReservoirs[idx].unpack();
}

void writeReservoir(const uint2 pixel, const Reservoir reservoir)
{
    const uint idx = encodeMortonCode(pixel);
    gOutputReservoirs[idx] = PackedReservoir(reservoir);
}

void RandomReplay(const uint2 currentPixel, const uint2 otherPixel, const uint replayIdx) {

}

Reservoir spatialRetrace<S: ISampleGenerator>(uint2 pixel, S sg) {
    Reservoir centralReservoir = readReservoir(pixel);
    if (centralReservoir.s.firstReconnectionableBounceIdx == 0)
    {
        // No reconnectionable bounces
        return centralReservoir;
    }

    uint2 neighbours[kMaxNeighbours];
    for (uint i = 0; i < kMaxNeighbours; i++)
    {
        float radius = kSampleRadius * sampleNext1D(sg);
        float angle = M_2PI * sampleNext1D(sg);
        neighbours[i] = {
            clamp(pixel.x + uint(radius * cos(angle)), 0, gFrameDim.x), clamp(pixel.y + uint(radius * sin(angle)), 0, gFrameDim.y)
        };
    }

    for(uint i = 0; i < kMaxNeighbours; i++) {
        Reservoir neighbourReservoir = readReservoir(neighbours[i]);

        // TODO: geometry check;
        // foo bar procedure

        if (neighbourReservoir.s.firstReconnectionableBounceIdx == 0)
        {
            // No reconnectionable bounces
            continue;
        }
        if (centralReservoir.s.firstNonDeltaInteractionIdx > 0 || neighbourReservoir.s.firstReconnectionableBounceIdx > 1)
        {
            RandomReplay(pixel, neighbours[i], neighbourReservoir.s.firstReconnectionableBounceIdx);
        }
    }
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
    if (any(pixel >= gFrameDim))
        return;
    SampleGenerator sg = SampleGenerator(pixel, gFrameCount*gFrameCount);
    writeReservoir(pixel, spatialRetrace(pixel, sg));
}
