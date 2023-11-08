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
import Rendering.PLT;
import LightSampling;
import Path;
import Params;
import CB;

// Inputs
Texture2D<PackedHitInfo> gVBuffer;
Texture2D<float4> gViewW; // Optional

// Outputs
RWTexture2D<float4> gOutputColor;

#define is_valid(name) (is_valid_##name != 0)

struct ShadowRayData
{
    bool visible;
}

float3 getPrimaryRayDir(uint2 launchIndex, uint2 launchDim, const Camera camera)
{
    if (false)
    {
        // If we have the view vector bound as a buffer, just fetch it. No need to compute anything.
        return -gViewW[launchIndex].xyz;
    }
    else
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

// BSDF sampling
bool pltSampleBSDF<
    S : ISampleGenerator>(const ShadingData sd, const IMaterialInstance bsdf, inout S sg, out BSDFSample bsdfSample, const float wavelength)
{
    const bool valid = bsdf.sample(sd, sg, bsdfSample, wavelength);
    if (!valid || bsdfSample.pdf == .0f)
        return false;
    return true;
}

ShadingData loadShadingData(const HitInfo hit, const float3 rayOrigin, const float3 rayDir, const ITextureSampler lod)
{
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
        v = gScene.getVertexData(displacedTriangleHit, -rayDir);
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
#if SCENE_HAS_GEOMETRY_TYPE(GEOMETRY_TYPE_SDF_GRID)
    if (hit.getType() == HitType::SDFGrid)
    {
        const SDFGridHit sdfGridHit = hit.getSDFGridHit();
        v = gScene.getVertexDataFromSDFGrid(sdfGridHit, rayOrigin, rayDir);
        materialID = gScene.getMaterialID(sdfGridHit.instanceID);
    }
#endif

    ShadingData sd = gScene.materials.prepareShadingData(v, materialID, -rayDir, lod);

    return sd;
}

bool traceShadowRay(float3 origin, float3 dir, float distance)
{
    RayDesc ray;
    ray.Origin = origin;
    ray.Direction = dir;
    ray.TMin = 0.f;
    ray.TMax = distance;
    ShadowRayData rayData;
    rayData.visible = false;
    TraceRay(
        gScene.rtAccel, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, 0xff /* instanceInclusionMask */, 1 /* hitIdx */, rayTypeCount,
        1 /* missIdx */, ray, rayData
    );
    return rayData.visible;
}

// float3 evalDirectAnalytic(
//     const ShadingData sd,
//     const IMaterialInstance bsdf,
//     inout SampleGenerator sg,
//     const float wavelength,
//     bool importanceSampleSpectrum
// )
// {
//     float3 outColor;
//     const uint lightCount = gScene.getLightCount();
//     if (lightCount == 0)
//         return float3(0.0f);
//     const uint lightIndex = min(uint(sampleNext1D(sg) * lightCount), lightCount - 1);
//     float invPdf = lightCount;
//     AnalyticLightSample ls;
//     let light = gScene.getLight(lightIndex);
//     if (!sampleLight(sd.posW, light, sg, wavelength, importanceSampleSpectrum, ls))
//     {
//         return float3(0.0f);
//     }
//     const bool isDistantEmitter = light.type == (uint)LightType::Directional || light.type == (uint)LightType::Distant;
//     const float A = light.surfaceArea; // mm^2
//     const float Omega = 4.f * M_PI * (1.f - sqr(light.cosSubtendedAngle));
//     const hwss_t L = ls.Li * invPdf;

//     // // Setup returned sample.

//     // // Offset shading position to avoid self-intersection.
//     // computeNewRayOrigin(sd, ls.dir);
//     // // No need to adjust the ray length to avoid self-intersections at the light.
//     // ls.distance = ls.distance;
//     // ls.dir = ls.dir;

//     const hwss_t wavelengths = ls.wavelengths;
//     PLTBeam beam;
//     if (isDistantEmitter)
//         beam = pltSourceBeamDistant(-ls.dir, Omega, L, wavelengths, 0.25f /*kSourcingMaxBeamOmega*/, false /*kForceFullyCoherent*/);
//     else
//         beam = pltSourceBeamArea(
//             light.posW, -ls.dir, A, ls.distance, L, wavelengths, 0.25f /*kSourcingMaxBeamOmega*/, false /*kForceFullyCoherent*/
//         );
//     const uint lobeTypes = bsdf.getLobes(sd);

//     const bool hasReflection = lobeTypes & uint(LobeType::Reflection);
//     const bool hasTransmission = lobeTypes & uint(LobeType::Transmission);
//     if (dot(ls.dir, sd.N) <= kMinCosTheta && !hasTransmission)
//         return float3(0.f);
//     if (dot(ls.dir, sd.N) >= -kMinCosTheta && !hasReflection)
//         return float3(0.f);
//     const float3 origin = computeRayOrigin(sd.posW, dot(sd.faceN, ls.dir) >= 0.f ? sd.faceN : -sd.faceN);
//     if (!traceShadowRay(origin, ls.dir, ls.distance))
//         return float3(0.0f);

//     beam.propagate(gScene.camera.data.posW);
//     bsdf.eval(sd, ls.dir, lobeTypes, beam);
//     const hwss_t pdfs = bsdf.lambdaPdf(sd, ls.dir, lobeTypes, beam, wavelengths);
//     beam.spectralPDFs *= pdfs;

//     float pathContribution = 1.0f;
//     if (true)
//     {
//         // MIS spectral contributions
//         const float sum = dot(beam.spectralPDFs, hwss_t(1.f));
//         pathContribution *= sum > FLT_EPSILON ? beam.spectralPDFs[0] / sum : .0f;
//     }
//     else
//         pathContribution *= 1.f / float(beam.hwss_comps);
//     // return pathContribution;
//     const hwss_t Li = beam.L * dot(sd.N, ls.dir);
//     // return SpectrumUtils.spectrumToRgb(Li, beam.wavelengths, beam.hwss_comps);
//     return max(float3(.0f), SpectrumUtils.spectrumToRgb(Li, beam.wavelengths, beam.hwss_comps) * pathContribution);
// }

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

bool NEE<S : ISampleGenerator>(
    inout float3 L,
    inout S sg,
    inout float hwssWeight,
    const float wavelength,
    const int bounceIdx,
    // const float3 wi,
    // const uint2 pixel,
    // const TriangleHit triangleHit,
    const ShadingData sd,
    // const VertexData V,
    // const uint matID,
    const IMaterialInstance bsdf,
    const BSDFProperties bsdfProp
)
{
    const uint lobes = bsdf.getLobes(sd);
    // MNEE and MSはしない

    const bool sampleReflection = (lobes & (uint)LobeType::NonDeltaReflection) != 0;
    const bool sampleTransmission = (lobes & (uint)LobeType::NonDeltaTransmission) != 0;
    if (!sampleReflection && !sampleTransmission)
        return false; // If bsdf has delta lobes.

    // sample light
    LightSample ls;
    const bool importanceSampleSpectrum = true; // TODO: move to params
    const bool valid = generateLightSample(sd, sampleReflection, sampleTransmission, sg, wavelength, importanceSampleSpectrum, ls);
    if (!valid || !any(ls.beam.L > 0.f))
        return false;
    // Update HWSS component
    // 代表波長以外を捨てる時
    // if (!mHWSSDoMIS &&)
    //     ls.beam.collapseToHeroWavelengthOnly();

    bool doMis = kDoMIS && ls.lightType != (uint)SampledLightType::Analytic;

    // Check visibility
    // V(wo)
    let visRayDesc = ls.getVisibilityRay();
    if (!traceShadowRay(visRayDesc.Origin, visRayDesc.Direction, visRayDesc.TMax))
        return true;
    if (doMis)
    {
        const float bsdfPdf = bsdf.pdf(sd, ls.dir, ls.beam.wavelengths.x);
        ls.beam.scale(MISWeight(ls.pdf, bsdfPdf));
    }

    // eval lighting
    // fs(wi,wo)*dot(wo,n)
    bsdf.eval(sd, ls.dir, (uint)LobeType::NonDelta, ls.beam);

    if (kHWSSDoMIS)
    {
        const hwss_t pdfs = bsdf.lambdaPdf(sd, ls.dir, (uint)LobeType::NonDelta, ls.beam, ls.beam.wavelengths);
        ls.beam.spectralPDFs *= pdfs;
    }
    // Le(x_D<->x_D-1)
    L = max(float3(.0f), SpectrumUtils.spectrumToRgb(ls.beam.L, ls.beam.wavelengths, ls.beam.hwss_comps));
    hwssWeight = HWSSWeight(ls.beam);
    return true;
}

float3 tracePath(const in uint2 pixel, const in uint2 frameDim)
{
    const float3 primaryRayOrigin = gScene.camera.getPosition();
    const float3 primaryRayDir = getPrimaryRayDir(pixel, frameDim, gScene.camera);
    const HitInfo hit = HitInfo(gVBuffer[pixel]);
    SampleGenerator sg = SampleGenerator(pixel, gFrameCount);
    const float wl = SpectrumSampler.sampleOne(sampleNext1D(sg));
    Path path = Path(sg, primaryRayOrigin, primaryRayDir, wl);

    bool useVBuffer = false;
    if (useVBuffer)
    {
        if (hit.isValid())
        {
            // DI
            {
                onHit(path, hit);
            }
            // GI
            if (!path.terminated)
            {
                ;
            }
        }
        else
        {
            onMiss(path);
        }
    }
    else
    {
        for (path.length = 0; path.length < kMaxBounces && !path.terminated;)
        {
            RayDesc ray;
            ray.Origin = path.origin;
            ray.Direction = path.dir;
            ray.TMin = 0.f;
            ray.TMax = kRayTMax;
            uint rayFlags = 0;
            TraceRay(gScene.rtAccel, rayFlags, 0xff, 0, rayTypeCount, 0, ray, path);
            break;
        }
    }

    return path.radiance;
}

void onHit(inout Path path, const HitInfo hit)
{
    let lod = ExplicitLodTextureSampler(0.f);
    const ShadingData sd = loadShadingData(hit, path.origin, path.dir, lod);
    let bsdf = gScene.materials.getMaterialInstance(sd, lod);
    const BSDFProperties bsdfProp = bsdf.getProperties(sd);
    {                                               // Emissibe Material Contribution
        const bool importanceSampleSpectrum = true; // TODO:
        // float3 Le = float3(0.f);
        // evalEmissive(Le, path.sg); TODO:
    }
    if (path.length >= kMaxBounces)
    {
        path.terminated = true;
        return;
    }

    { // NEE Contribution
        float3 L = float3(0.f);
        float hwssWeight = 0.f;
        NEE(L, path.sg, hwssWeight, path.wavelength, 0, sd, bsdf, bsdfProp);
        path.thp *= hwssWeight;
        path.radiance += path.thp * L;
    }
    { // PRR //update path
        BSDFSample bsdfSample;
        const float prr = 0.9f;
        const bool sampleValid = pltSampleBSDF(sd, bsdf, path.sg, bsdfSample, path.wavelength);
        if (sampleValid && sampleNext1D(path.sg) <= prr)
        {
            const bool isDelta = bsdfSample.isLobe(LobeType::Delta);
            path.dir = bsdfSample.wo;
            path.origin = sd.computeNewRayOrigin();
            path.thp *= bsdfSample.weight;
            path.lastNonDeltaPdf = !isDelta ? bsdfSample.pdf : path.lastNonDeltaPdf;
        }
        else
        {
            path.terminated = true;
            return;
        }
    }
    path.length++;
}

void onMiss(inout Path path)
{
    path.terminated = true;
    {
        float3 Le = gScene.envMap.eval(WorldRayDirection());
        path.radiance += path.thp * Le;
    }
}

// Miss Shader
[shader("miss")]
void scatterMiss(inout Path path)
{
    onMiss(path);
}
[shader("miss")]
void shadowMiss(inout ShadowRayData rayData)
{
    rayData.visible = true;
}

// Handle hit of Basic Trinagle
[shader("closesthit")]
void scatterTriangleMeshClosestHit(inout Path path, BuiltInTriangleIntersectionAttributes attribs)
{
    // Shading data
    TriangleHit triangleHit;
    triangleHit.instanceID = getGeometryInstanceID();
    triangleHit.primitiveIndex = PrimitiveIndex();
    triangleHit.barycentrics = attribs.barycentrics;
    const PackedHitInfo hit = triangleHit.pack();
    onHit(path, HitInfo(hit));
}

[shader("anyhit")]
void scatterTriangleMeshAnyHit(inout Path path, BuiltInTriangleIntersectionAttributes attribs)
{
    // Alpha test for non-opaque geometry.
    GeometryInstanceID instanceID = getGeometryInstanceID();
    VertexData v = getVertexData(instanceID, PrimitiveIndex(), attribs);
    const uint materialID = gScene.getMaterialID(instanceID);
    if (gScene.materials.alphaTest(v, materialID, 0.f))
        IgnoreHit();
}
[shader("anyhit")]
void shadowTriangleMeshAnyHit(inout ShadowRayData rayData, BuiltInTriangleIntersectionAttributes attribs)
{
    // Alpha test for non-opaque geometry.
    GeometryInstanceID instanceID = getGeometryInstanceID();
    VertexData v = getVertexData(instanceID, PrimitiveIndex(), attribs);
    const uint materialID = gScene.getMaterialID(instanceID);
    if (gScene.materials.alphaTest(v, materialID, 0.f))
        IgnoreHit();
}

// Handle hit of Displacemented Triangle
[shader("closesthit")]
void scatterDisplacedTriangleMeshClosestHit() {}
[shader("intersection")]
void displacedTriangleMeshIntersection() {}

// Handle hit of Curve
[shader("closesthit")]
void scatterCurveMeshClosestHit() {}
[shader("intersection")]
void curveMeshIntersection() {}

// Handle hit of SDFGrid
[shader("closesthit")]
void scatterSdfGridMeshClosestHit() {}
[shader("intersection")]
void sdfGridMeshIntersection() {}

// Ray-generation
[shader("raygeneration")]
void rayGen()
{
    uint2 pixel = DispatchRaysIndex().xy;
    uint2 frameDim = DispatchRaysDimensions().xy;
    float3 finalColor = tracePath(pixel, frameDim);
    gOutputColor[pixel] = float4(finalColor, 1.0f);
}
