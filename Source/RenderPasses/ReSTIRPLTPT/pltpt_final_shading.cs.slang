#pragma once

#include "Scene/SceneDefines.slangh"
#include "Utils/Math/MathConstants.slangh"

#include "pltpt_constants.slangh"
#include "pltpt_debug.slangh"

#include "DebugViewType.slangh"

#include "ShadowRays.slangh"
#include "Manifolds.slangh"

import Scene.ShadingData;
import Scene.Scene;

import Utils.HWSS;
import Utils.Math.MathHelpers;
import Utils.Sampling.SampleGenerator;
import Utils.Geometry.GeometryHelpers;
import Utils.Color.SpectrumSampler;
import Utils.Color.SpectrumUtils;

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


cbuffer CB
{
    uint gFrameCount; // Frame count since scene was loaded.
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
Texture2D<float4> gIndirectIllumination;
Texture2D<float4> gDirectIllumination;

// Outputs
RWTexture2D<float4> gOutputColor;

