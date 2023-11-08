#pragma once

import Scene.Scene;
import Scene.HitInfo;

import Rendering.Materials.LobeType;

import Utils.HWSS;
import Utils.Color.SpectrumSampler;
import Utils.Math.MathHelpers;
import Utils.Sampling.SampleGenerator;
import Utils.Math.MathHelpers;

struct Path
{
    // 16B
    SampleGenerator sg;

    // 24B
    float3 origin;
    float3 dir;
    // float3 normal;
    // 4B
    float wavelength;

    // 24B
    float3 radiance;
    float3 thp;

    // 4B
    float lastNonDeltaPdf;
    // 4B
    uint length;

    bool terminated;

    __init(SampleGenerator sg, float3 rayGenOrigin, float3 rayGenDir, float samplingWaveLength)
    {
        this.wavelength = samplingWaveLength;
        this.origin = rayGenOrigin;
        this.dir = rayGenDir;
        this.radiance = float3(0.0f);
        this.thp = float3(1.0f);
        this.lastNonDeltaPdf = 1.0f;
        this.terminated = false;
        this.sg = sg;
        this.length = 0;
    }
}
