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

import Rendering.PLT;
import LightSampling;
import Path;
import Params;
// import CB;
import Reservoir;
import RISPathTracer;

// Inputs
Texture2D<PackedHitInfo> gVBuffer;
Texture2D<float4> gViewW; // Optional

// Outputs
RWTexture2D<float4> gOutputColor;

ParameterBlock<RISPathTracer> gPathTracer;

#define is_valid(name) (is_valid_##name != 0)

struct ShadowRayData
{
    bool visible;
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

[mutating]
void onHit(inout Path path, const HitInfo hit)
{
    // gPathTracer.preprocessOnHit(path.dir, hit, bsdf, );
    let lod = ExplicitLodTextureSampler(0.f);
    const ShadingData sd = loadShadingData(hit, path.origin, path.dir, lod);
    let bsdf = gScene.materials.getMaterialInstance(sd, lod);
    const BSDFProperties bsdfProp = bsdf.getProperties(sd);

    {                                               // Emissibe Material Contribution
        const bool importanceSampleSpectrum = true; // TODO:
                                                    // float3 Le = float3(0.f);
                                                    // evalEmissive(Le, path.sg); TODO:
        hwss_t sampledWavelengths;
        hwss_t Le =
            gScene.sampleSpectrum(bsdfProp.emissionSpectralId, path.wavelength, path.sg, importanceSampleSpectrum, sampledWavelengths);
        Le *= SpectrumUtils.rgbToSpectrum(bsdfProp.emissionRGB, sampledWavelengths);
    }

    if (path.length >= kMaxBounces)
    {
        path.terminated = true;
        return;
    }
    LightSample ls;
    gPathTracer.emitterSampling(ls, path.wavelength, sd, bsdf, bsdfProp, path.sg);
    let visRayDesc = ls.getVisibilityRay();
    float3 L = float3(0.0f);
    if (traceShadowRay(visRayDesc.Origin, visRayDesc.Direction, visRayDesc.TMax))
    {
        gPathTracer.evalThroughput(ls.beam, path.length, DispatchRaysIndex().xy);
        path.radiance += gPathTracer.evalRadiance(ls.beam, path.pdf * path.thp_mod);
    }
    BSDFSample bsdfSample;
    gPathTracer.constructPathByBSDFSampling(path, sd, bsdf, bsdfSample);
    gPathTracer.recordPath(hit, bsdfSample, path.length, DispatchRaysIndex().xy);
}

void onMiss(inout Path path)
{
    path.terminated = true;
    {
        float3 Le = gScene.envMap.eval(WorldRayDirection());
        // path.radiance += path.thp * Le;
    }
}

float3 tracePath(const in uint2 pixel, const in uint2 frameDim)
{
    const float3 primaryRayOrigin = gScene.camera.getPosition();
    const float3 primaryRayDir = getPrimaryRayDir(pixel, frameDim, gScene.camera);
    SampleGenerator sg = SampleGenerator(pixel, gPathTracer.gFrameCount);
    const float wl = SpectrumSampler.sampleOne(sampleNext1D(sg)); // use RIS instead of random sampling?
    Path path = Path(sg, primaryRayOrigin, primaryRayDir, wl);
    gPathTracer.init(primaryRayDir, pixel);
    {
        for (; path.length < kMaxBounces && !path.terminated;)
        {
            RayDesc ray;
            ray.Origin = path.origin;
            ray.Direction = path.dir;
            ray.TMin = 0.f;
            ray.TMax = kRayTMax;
            uint rayFlags = 0;
            TraceRay(gScene.rtAccel, rayFlags, 0xff, 0, rayTypeCount, 0, ray, path);
        }
    }
    return path.radiance;
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

