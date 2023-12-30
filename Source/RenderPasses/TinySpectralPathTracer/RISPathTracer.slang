#pragma once

#include "Scene/SceneDefines.slangh"
#include "Utils/Math/MathConstants.slangh"

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
import Utils.Geometry.GeometryHelpers;
import Utils.Sampling.SampleGenerator;
import Rendering.Lights.LightHelpers;
import Rendering.Utils.LightsSamplingUtils;
import Rendering.Lights.EmissiveLightSampler;
import Rendering.Materials.BxDF;
import Rendering.Materials.PLT.Mueller;
// import Rendering.Materials.PLT;
import Utils.Color.ColorHelpers;

import Rendering.Lights.EmissiveLightSampler;
import Rendering.Lights.EnvMapSampler;

import Rendering.PLT;
import LightSampling;
import Path;
import Params;
import CB;
import Reservoir;

struct RISPathTracer
{
    uint gFrameCount;
    uint2 gFrameDim;
    EnvMapSampler envMapSampler;
    EmissiveLightSampler emissiveSampler;
    RWStructuredBuffer<PathSurface> gPathData;
    // Avoid to compile-error, use raw macro defined by host
    // PathSurface[MAX_BOUNCES] gPathData;

    enum class PropagationDirection
    {
        ToLight,
        ToCamera,
    };

    inline uint pixel1D(uint2 pixel) { return pixel.x + gFrameDim.x * pixel.y; }

    float RR(const float rrVal, const float rrE, const float sample)
    {
        const float p = pow(rrVal, rrE);

        return sample < p ? .0f : 1.f - p;
    }

    float3 getPrimaryRayDir(uint2 launchIndex, uint2 launchDim, const Camera camera)
    {
        {
            // Compute the view vector. This must exactly match what the G-buffer pass is doing (jitter etc.).
            // Note that we do not take depth-of-field into account as it would require exactly matching the
            // sample generator between the passes, which is error prone. The host side will issue a warning instead.
            return camera.computeRayPinhole(launchIndex, launchDim).dir;
        }
    }

    float MISWeight(float p0, float p1, float n0 = 1.f, float n1 = 1.f)
    {
        // Balance heuristic
        float q0 = n0 * p0;
        float q1 = n1 * p1;
        return q0 / (q0 + q1);
    }

    float HWSSWeight(const PLTBeam beam)
    {
        if (kHWSSDoMIS)
        {
            // MIS spectral contributions
            const float sum = dot(beam.spectralPDFs, hwss_t(1.f));
            return sum > FLT_EPSILON ? beam.spectralPDFs[0] / sum : .0f;
        }
        else
            return 1.f / float(beam.hwss_comps);
    }

    void forwardHWSSMis(const IMaterialInstance bsdf, const ShadingData sd, const float3 wo, const uint sampledBsdfLobe, inout PLTBeam beam)
    {
        if (kHWSSDoMIS)
        {
            const hwss_t pdfs = bsdf.lambdaPdf(sd, wo, sampledBsdfLobe, beam, beam.wavelengths);
            beam.spectralPDFs *= pdfs;
        }
    }

    // BSDF sampling
    bool pltSampleBSDF<S : ISampleGenerator>(
        const ShadingData sd,
        const IMaterialInstance bsdf,
        inout S sg,
        out BSDFSample bsdfSample,
        const float wavelength
    )
    {
        const bool valid = bsdf.sample(sd, sg, bsdfSample, wavelength);
        if (!valid || bsdfSample.pdf == .0f)
            return false;
        return true;
    }

    ShadingData loadShadingData(const HitInfo hit, const float3 dir, const ITextureSampler lod, const PropagationDirection lightDir)
    {
        const float3 toPrevSurface = lightDir == PropagationDirection::ToLight ? -dir : dir;
        VertexData v = {};
        uint materialID = {};

#if SCENE_HAS_GEOMETRY_TYPE(GEOMETRY_TYPE_TRIANGLE_MESH)
        if (hit.getType() == HitType::Triangle)
        {
            const TriangleHit triangleHit = hit.getTriangleHit();
            v = gScene.getVertexData(triangleHit);
            materialID = gScene.getMaterialID(triangleHit.instanceID);
        }
#endif
#if SCENE_HAS_GEOMETRY_TYPE(GEOMETRY_TYPE_DISPLACED_TRIANGLE_MESH)
        if (hit.getType() == HitType::DisplacedTriangle)
        {
            const DisplacedTriangleHit displacedTriangleHit = hit.getDisplacedTriangleHit();
            v = gScene.getVertexData(displacedTriangleHit, toPrevSurface);
            materialID = gScene.getMaterialID(displacedTriangleHit.instanceID);
        }
#endif
#if SCENE_HAS_GEOMETRY_TYPE(GEOMETRY_TYPE_CURVE)
        if (hit.getType() == HitType::Curve)
        {
            const CurveHit curveHit = hit.getCurveHit();
            v = gScene.getVertexDataFromCurve(curveHit);
            materialID = gScene.getMaterialID(curveHit.instanceID);
        }
#endif

        ShadingData sd = gScene.materials.prepareShadingData(v, materialID, toPrevSurface, lod);

        return sd;
    }

    bool evalEmissive<S : ISampleGenerator>(
        inout float3 L,
        inout S sg,
        const float wavelength,
        const float lastNonDeltaPdf,
        const ShadingData sd,
        const BSDFProperties bsdfProp,
        const TriangleHit triangleHit
    )
    {
        // TODO:
        // if (kUseEmissiveLights && bsdfProp.isEmissive)
        // {
        //     TriangleLightHit hit;
        //     hit.triangleIndex = gScene.lightCollection.getTriangleIndex(triangleHit.instanceID, triangleHit.primitiveIndex);
        //     hit.posW = sd.posW;
        //     hit.normalW = sd.frontFacing ? sd.faceN : -sd.faceN;
        //     const float lightPdf =
        //         getEmissiveSelectionProbability() * emissiveSampler.evalPdf(solveData.pathOrigin, solveData.pathNormal, false, hit);
        //     const float misWeight = MISWeight(lastNonDeltaPdf, lightPdf);

        //     // Emitted intensity
        //     hwss_t sampledWavelengths;
        //     hwss_t Le = gScene.sampleSpectrum(bsdfProp.emissionSpectralId, wavelength, sg, importanceSampleSpectrum, sampledWavelengths);
        //     Le *= misWeight * SpectrumUtils.rgbToSpectrum(bsdfProp.emissionRGB, sampledWavelengths);
        // }
        return true;
    }

    void preprocessOnHit(const float3 rayComingDir, const HitInfo hit, out IMaterialInstance bsdf, out BSDFProperties bsdfProp)
    {
        let lod = ExplicitLodTextureSampler(0.f);
        const ShadingData sd = loadShadingData(hit, rayComingDir, lod, PropagationDirection::ToLight);
        bsdf = gScene.materials.getMaterialInstance(sd, lod);
        bsdfProp = bsdf.getProperties(sd);
    }

    // for NEE
    bool emitterSampling<S : ISampleGenerator>(
        inout LightSample ls,
        const float wavelength,
        const ShadingData sd,
        const IMaterialInstance bsdf,
        const BSDFProperties bsdfProp,
        inout S sg
    )
    {
        const uint lobes = bsdf.getLobes(sd);
        // MNEE and MSはしない

        const bool sampleReflection = (lobes & (uint)LobeType::NonDeltaReflection) != 0;
        const bool sampleTransmission = (lobes & (uint)LobeType::NonDeltaTransmission) != 0;
        if (!sampleReflection && !sampleTransmission)
            return false; // If bsdf has delta lobes.
        if (kUSERISDirectIllumination)
        { // TODO:
        }
        else
        {
            const bool importanceSampleSpectrum = true;
            const bool valid = generateLightSample(sd, sampleReflection, sampleTransmission, sg, wavelength, importanceSampleSpectrum, ls);
            if (!valid || !any(ls.beam.L > 0.f))
                return false;
        }
        return true;
    }

    void evalThroughput(inout PLTBeam beam, const int pathlength, const uint2 pixel, )
    {
        let lod = ExplicitLodTextureSampler(0.0f);
        for (int i = pathlength; i > 0; i--)
        {
            int idx = pixel1D(pixel) + i;
            // evaluate path of bsdf throughput from emittor to camera.
            const HitInfo hit = gPathData[idx].hit;
            const float3 goingDir = gPathData[idx].dir;
            const uint lobe = gPathData[idx].lobe;
            const float3 comingDir = gPathData[pixel1D(pixel) + i - 1].dir;
            const ShadingData forwardSd = loadShadingData(hit, goingDir, lod, PropagationDirection::ToCamera);
            beam.propagate(forwardSd.posW);
            let bsdf = gScene.materials.getMaterialInstance(forwardSd, lod);
            bsdf.eval(forwardSd, -comingDir, lobe, beam);
            forwardHWSSMis(bsdf, forwardSd, -comingDir, lobe, beam);
        }

        // for polarization
        {
            const float k = M_2PI / (1e-3f * beam.wavelengths.x);
            beam.propagate(gScene.camera.data.posW);
            const float polarizationIntensity = gScene.camera.data.polarizer;
            const float polarizationTheta = gScene.camera.data.polarizerTheta;
            if (polarizationIntensity > .0f)
            {
                // Rotate to camera frame
                const float3 cameraW = normalize(gScene.camera.data.cameraW);
                const float3 cameraU = normalize(gScene.camera.data.cameraU);
                beam.rotateFrame(cameraU, -cameraW);

                // Polarize
                const float4x4 P = (1.f - polarizationIntensity) * ident4() + polarizationIntensity * MuellerPolarizer(polarizationTheta);
                for (int j = 0; j < beam.hwss_comps; ++j)
                    beam.setSP(j, mul(P, beam.getSP(j)));
            }
        }
    }

    float3 evalRadiance(const PLTBeam beam, float combinedPathPdf)
    {
        const float contrib = HWSSWeight(beam) / combinedPathPdf;
        float3 L = max(float3(.0f), SpectrumUtils.spectrumToRgb(beam.L, beam.wavelengths, beam.hwss_comps));
        return L * contrib;
    }

    bool constructPathByBSDFSampling(inout Path path, const ShadingData sd, const IMaterialInstance bsdf, out BSDFSample bsdfSample)
    {
        // BSDF Sampling
        const bool sampleValid = pltSampleBSDF(sd, bsdf, path.sg, bsdfSample, path.wavelength);
        if (!sampleValid)
        {
            path.terminated = true;
            return false;
        }

        { // PRR //update path
            // do russian roulette
            const float rcp_thp = RR(1.f - path.weight, 2.f, sampleNext1D(path.sg));

            if (rcp_thp != 0.0f)
            {
                const bool isDelta = bsdfSample.isLobe(LobeType::Delta);
                path.dir = bsdfSample.wo;
                path.origin = sd.computeNewRayOrigin();
                /*
                わかったこととして、スループットのbsdf項を光源方向からbeamを育てないと正しい値にならなさそうな感じ
                weightはbackward-weightらしいので、逆向き。
                */
                path.weight *= bsdfSample.weight;
                path.pdf *= bsdfSample.pdf;
                path.thp_mod *= rcp_thp;
                //
                path.lastNonDeltaPdf = !isDelta ? bsdfSample.pdf : path.lastNonDeltaPdf;
                path.length++;
                return true;
            }
            else
            {
                path.terminated = true;
                return false;
            }
        }
    }

    void recordPath(const HitInfo hit, const BSDFSample bsdfSample, const int pathLength, const uint2 pixel)
    {
        int idx = pixel1D(pixel) + pathLength;
        gPathData[idx].dir = bsdfSample.wo;
        gPathData[idx].hit = hit;
        gPathData[idx].lobe = bsdfSample.lobe;
    }

    void init(const float3 primaryRayDir, const uint2 pixel)
    {
        int idx = pixel1D(pixel) + 0;
        gPathData[idx].dir = primaryRayDir;
    }
}
