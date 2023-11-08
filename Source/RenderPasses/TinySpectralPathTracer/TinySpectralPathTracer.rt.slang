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
import Rendering.Materials.BxDF;
import Rendering.Materials.PLT.Mueller;
// import Rendering.Materials.PLT;
import Rendering.PLT;

import Path;
import CB;

// Inputs
Texture2D<PackedHitInfo> gVBuffer;
Texture2D<float4> gViewW; // Optional

// Outputs
RWTexture2D<float4> gOutputColor;

#define is_valid(name) (is_valid_##name != 0)
static const uint kMaxBounces = MAX_BOUNCES;

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

float3 evalDirectAnalytic(
    const ShadingData sd,
    const IMaterialInstance bsdf,
    inout SampleGenerator sg,
    const float wavelength,
    bool importanceSampleSpectrum
)
{
    float3 outColor;
    const uint lightCount = gScene.getLightCount();
    if (lightCount == 0)
        return float3(0.0f);
    const uint lightIndex = min(uint(sampleNext1D(sg) * lightCount), lightCount - 1);
    float invPdf = lightCount;
    AnalyticLightSample ls;
    let light = gScene.getLight(lightIndex);
    if (!sampleLight(sd.posW, light, sg, wavelength, importanceSampleSpectrum, ls))
    {
        return float3(0.0f);
    }
    const bool isDistantEmitter = light.type == (uint)LightType::Directional || light.type == (uint)LightType::Distant;
    const float A = light.surfaceArea; // mm^2
    const float Omega = 4.f * M_PI * (1.f - sqr(light.cosSubtendedAngle));
    const hwss_t L = ls.Li * invPdf;

    // // Setup returned sample.

    // // Offset shading position to avoid self-intersection.
    // ls.origin = computeNewRayOrigin(sd, ls.dir);
    // // No need to adjust the ray length to avoid self-intersections at the light.
    // ls.distance = ls.distance;
    // ls.dir = ls.dir;

    const hwss_t wavelengths = ls.wavelengths;
    PLTBeam beam;
    if (isDistantEmitter)
        beam = pltSourceBeamDistant(-ls.dir, Omega, L, wavelengths, 0.25f /*kSourcingMaxBeamOmega*/, false /*kForceFullyCoherent*/);
    else
        beam = pltSourceBeamArea(
            light.posW, -ls.dir, A, ls.distance, L, wavelengths, 0.25f /*kSourcingMaxBeamOmega*/, false /*kForceFullyCoherent*/
        );
    const uint lobeTypes = bsdf.getLobes(sd);

    const bool hasReflection = lobeTypes & uint(LobeType::Reflection);
    const bool hasTransmission = lobeTypes & uint(LobeType::Transmission);
    if (dot(ls.dir, sd.N) <= kMinCosTheta && !hasTransmission)
        return float3(0.f);
    if (dot(ls.dir, sd.N) >= -kMinCosTheta && !hasReflection)
        return float3(0.f);
    const float3 origin = computeRayOrigin(sd.posW, dot(sd.faceN, ls.dir) >= 0.f ? sd.faceN : -sd.faceN);
    if (!traceShadowRay(origin, ls.dir, ls.distance))
        return float3(0.0f);

    beam.propagate(gScene.camera.data.posW);
    bsdf.eval(sd, ls.dir, lobeTypes, beam);
    const hwss_t pdfs = bsdf.lambdaPdf(sd, ls.dir, lobeTypes, beam, wavelengths);
    beam.spectralPDFs *= pdfs;

    float pathContribution = 1.0f;
    if (true)
    {
        // MIS spectral contributions
        const float sum = dot(beam.spectralPDFs, hwss_t(1.f));
        pathContribution *= sum > FLT_EPSILON ? beam.spectralPDFs[0] / sum : .0f;
    }
    else
        pathContribution *= 1.f / float(beam.hwss_comps);
    // return pathContribution;
    const hwss_t Li = beam.L * dot(sd.N, ls.dir);
    // return SpectrumUtils.spectrumToRgb(Li, beam.wavelengths, beam.hwss_comps);
    return max(float3(.0f), SpectrumUtils.spectrumToRgb(Li, beam.wavelengths, beam.hwss_comps) * pathContribution);
}

float3 tracePath(const in uint2 pixel, const in uint2 frameDim)
{
    const float3 primaryRayOrigin = gScene.camera.getPosition();
    const float3 primaryRayDir = getPrimaryRayDir(pixel, frameDim, gScene.camera);

    uint rayFlags = 0;
    SampleGenerator sg = SampleGenerator(pixel, gFrameCount);
    const float wl = SpectrumSampler.sampleOne(sampleNext1D(sg));

    Path path = Path(sg, primaryRayOrigin, primaryRayDir, wl);
    for (path.length = 0; path.length < kMaxBounces && !path.terminated;)
    {
        RayDesc ray;
        ray.Origin = path.origin;
        ray.Direction = path.dir;
        ray.TMin = 0.f;
        ray.TMax = FLT_MAX;
        TraceRay(gScene.rtAccel, rayFlags, 0xff, 0, rayTypeCount, 0, ray, path);
        break;
    }
    return path.radiance;
}

// Miss Shader
[shader("miss")]
void scatterMiss(inout Path path)
{
    path.terminated = true;

    {
        float3 Le = gScene.envMap.eval(WorldRayDirection());
        path.radiance += path.thp * Le;
    }
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
    const PackedHitInfo hitInfo = triangleHit.pack();

    const VertexData v = gScene.getVertexData(triangleHit);
    const uint materialID = gScene.getMaterialID(triangleHit.instanceID);
    let lod = ExplicitLodTextureSampler(0.f);

    const float3 wi = -path.dir;
    const ShadingData sd = gScene.materials.prepareShadingData(v, materialID, wi, lod);
    let bsdf = gScene.materials.getMaterialInstance(sd, lod);
    const BSDFProperties bsdfProp = bsdf.getProperties(sd);
    path.radiance = evalDirectAnalytic(sd, bsdf, path.sg, path.wavelength, true);

    // Add  emitted light;
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
