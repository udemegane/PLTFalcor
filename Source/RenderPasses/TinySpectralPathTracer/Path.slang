#pragma once

import Scene.Scene;
import Scene.HitInfo;

import Rendering.Materials.LobeType;

import Utils.HWSS;
import Utils.Color.SpectrumSampler;
import Utils.Math.MathHelpers;
import Utils.Sampling.SampleGenerator;
import Utils.Math.MathHelpers;
import Params;

struct Path
{
    // 16B
    SampleGenerator sg;

    // 24B
    float3 origin;
    float3 dir;
    // 4B
    float wavelength;

    // 24B
    float3 radiance;
    float weight;
    float pdf;
    float thp_mod;

    // 4B
    float lastNonDeltaPdf;
    // 4B
    uint length;

    bool terminated;

#if ENABLE_DEBUG_FEATURES
    float3 debugColor1;
    float3 debugColor2;
#endif

    __init(SampleGenerator sg, float3 rayGenOrigin, float3 rayGenDir, float samplingWaveLength)
    {
        this.wavelength = samplingWaveLength;
        this.origin = rayGenOrigin;
        this.dir = rayGenDir;
        this.radiance = float3(0.0f);
        this.weight = 1.0f;
        this.pdf = 1.0f;
        this.thp_mod = 1.0f;
        this.lastNonDeltaPdf = 1.0f;
        this.terminated = false;
        this.sg = sg;
        this.length = 0;
    }
}

struct PathSurface
{
    PackedHitInfo encodedHit;

    float2 encodedDir;

    // BSDF Lobe
    uint lobe;
    float pathPdf;
    float lastNonDeltaPdf;
    float wavelength;
    // Infomation of Surface x_i
    property hit : HitInfo
    {
        get {
            return HitInfo(encodedHit);
        }
        set {
            encodedHit = newValue.data;
        }
    }

    // From current surface x_i to next surface x_i+1, sampled by current BSDF
    // In other words, propagation direction to emitter.
    property dir : float3
    {
        get {
            float3 outdir = float3(0.0f);
            outdir.x = encodedDir.x;
            outdir.y = encodedDir.y;
            outdir.z = sqrt(1.0f - dot(encodedDir, encodedDir));
            return outdir;
        }
        set {
            float3 ndir = normalize(newValue);
            encodedDir.x = dir.x;
            encodedDir.y = dir.y;
        }
    }
}

