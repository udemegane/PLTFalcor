import Utils.HWSS;
import Rendering.Utils.LightsSamplingUtils;
import Rendering.Materials.LobeType;

import Utils.Math.PackedFormats;
import Utils.Math.MathHelpers;

import Utils.Color.SpectrumUtils;

#define DISTANCE_THRESHOLD 1.0f
struct PathReconstructionData
{
    ////////////////////////
    // Sampled Light Data //
    ////////////////////////
    hwss_t Le;              ///< Emitted radiance.
    float wavelength;       ///< Hero-Wavelength of the sampled light.
    float pdf;              ///< Pdf with respect to solid angle at the shading point.
    float3 origin;          ///< Ray origin for visibility evaluation (offseted to avoid self-intersection).
    float distance;         ///< Ray distance for visibility evaluation (shortened to avoid self-intersection).
    float3 dir;             ///< Ray direction for visibility evaluation (normalized).
    float3 posW;            ///< Shading point position in world space.
    uint LightType;         ///< Type of the sampled light, Analytical, EnvMap or Mesh.
    bool isDistantEmitter;  ///< True if the sampled light is a distant emitter, Sun, EnvMap, etc...
    float selectionPdf;     ///< Pdf of the light-type selection.
    float Size;             ///< Measure-independent size of the light source, Omega or A.
    /////////////////////////

    /////////////////////////////////////
    // References to Path-Vertex array //
    /////////////////////////////////////
    uint lastBounceIdx;                 ///< Index of the last bounce of the path.
    // int firstDispersiveInteractionIdx;  ///< -1 if no dispersive interaction
    int firstReconnectionableBounceIdx; ///< -1 if no reconnectionable bounce
    int firstNonDeltaInteractionIdx;    ///< -1 if no non-delta interaction
    // bool hasDispersiveInteractionBeforeReconnectionableBounce; ///< True if there is a dispersive interaction before the reconnectionable bounce.
    float jacobianCounterpart;          ///< Jacobian of the transformation from solid angle to area measure
                                        ///  and the ratio of bsdf sampling pdfs which is needed for PSS ran
                                        ///  -dom-valiable transformation.

    uint2 pixel;                        ///< Pixel coordinates of the shading point for SampleGenerator-Seed.
    uint age;                           ///< Age of the sample, for the Seed. This become old when frame changes.
                                        ///  Note: Very careful when using this. The seed is important for PSS
                                        ///  random-replay. The seed is exactly the same as the one which was
                                        ///  used to generate the path.
    float RMISWeight;                   ///< MIS weight for the resampling of the path.

    [mutating]
    void setLightSample(
        hwss_t Le,
        float pdf,
        float3 origin,
        float distance,
        float3 dir,
        float3 posW,
        float wavelength,
        bool isDistantEmitter,
        float Size)
    {
        this.Le = Le;
        this.pdf = pdf;
        this.origin = origin;
        this.distance = distance;
        this.dir = dir;
        this.posW = posW;
        this.wavelength = wavelength;
        this.isDistantEmitter = isDistantEmitter;
        this.Size = Size;
    }

    [mutating]
    void setLightType(uint LightType, float selectionPdf)
    {
        this.LightType = LightType;
        this.selectionPdf = selectionPdf;
    }

    [mutating]
    void setPathData(
        uint lastBounceIdx,
        int firstNonDeltaInteractionIdx,
        int firstReconnectionableBounceIdx,
        uint2 pixel,
        uint age)
    {
        this.lastBounceIdx = lastBounceIdx;
        this.firstNonDeltaInteractionIdx = firstNonDeltaInteractionIdx;
        this.firstReconnectionableBounceIdx = firstReconnectionableBounceIdx;
        this.pixel = pixel;
        this.age = age;
    }

    [mutating]
    void setJacobianCounterpart(float jacobianCounterpart)
    {
        this.jacobianCounterpart = jacobianCounterpart;
    }

    [mutating]
    void setRMISWeight(float RMISWeight)
    {
        this.RMISWeight = RMISWeight;
    }

    static bool isReconnectionable(uint prevBsdfLobeType, uint currentBsdfLobeType, float3 prevPosW, float3 currentPosW)
    {
        const bool sampleReflection = (currentBsdfLobeType & (uint)LobeType::NonDeltaReflection) != 0;
        const bool sampleTransmission = (currentBsdfLobeType & (uint)LobeType::NonDeltaTransmission) != 0;
        const float3 dir = currentPosW - prevPosW;
        const bool distanceOk = dot(dir,dir) > DISTANCE_THRESHOLD;
        return (sampleReflection || sampleTransmission) && distanceOk;
    }

    static float computeJacobianCounterpart(float prevSamplingPdf, float currSamplingPdf, float cos_phi, float3 prevPosW, float3 currPosW)
    {
        const float3 toCurr = currPosW - prevPosW;
        // Jacobian of the transformation from solid angle to area measure and PSS
        return prevSamplingPdf * (cos_phi/dot(toCurr, toCurr)) * currSamplingPdf;
    }
};

enum class PackedComponentsMask: uint
{

    // 2bits, X
    LightType                      = 0b00000000000000000000000000000011,
    // 4bits, X
    LastBounceIdx                  = 0b00000000000000000000000000111100,
    // 4bits, X
    FirstNonDeltaInteractionIdx    = 0b00000000000000000000001111000000,
    // 4bits, X
    FirstReconnectionableBounceIdx = 0b00000000000000000011110000000000,
    // 8bits, X
    Age                            = 0b00000000001111111100000000000000,
    // 1bit, X
    IsDistantEmitter               = 0b00000000010000000000000000000000,
    // 9bits, X
    WaveLength                     = 0b11111111100000000000000000000000,
    // ------------Sum:32bit-------------
    // 12bit, Y
    PixelX                         = 0b00000000000000000000111111111111,
    // 12bit, Y
    PixelY                         = 0b00000000111111111111000000000000,

}

#ifndef HWSS_SAMPLES
#define HWSS_SAMPLES 1
#endif

struct PackedPathReconstructionData
{
    //52~64 bytes
    // 4 * 1~4 = 4~16 bytes
    // hwss_t Le; // In default, hwss_t is 4 floats. (16 bytes)
#if HWSS_SAMPLES == 1
    // 4B
    float L1;
#endif
#if HWSS_SAMPLES == 2
    // 8B
    float L1;
    float L2;
#endif
#if HWSS_SAMPLES == 3
    // 12B
    float L1;
    float L2;
    float L3;
#endif
#if HWSS_SAMPLES == 4
    // 16B
    float L1;
    float L2;
    float L3;
    float L4;
#endif
    // 4 * 12 = 48 bytes
    float pdf;
    // float origin // Currently dont support dynamic Scene.(If the scene is dynamic, the origin is needed for visibility evaluation.)
    float distance;
    float2 encodedDir;
    float3 posW;
    float selectionPdf;
    float Size;
    float jacobianCounterpart;
    uint2 packedComponents;
    __init(PathReconstructionData source)
    {
#if HWSS_SAMPLES == 1
        L1 = source.Le[0];
#endif
#if HWSS_SAMPLES == 2
        L1 = source.Le[0];
        L2 = source.Le[1];
#endif
#if HWSS_SAMPLES == 3
        L1 = source.Le[0];
        L2 = source.Le[1];
        L3 = source.Le[2];
#endif
#if HWSS_SAMPLES == 4
        L1 = source.Le[0];
        L2 = source.Le[1];
        L3 = source.Le[2];
        L4 = source.Le[3];
#endif
        this.pdf = source.pdf;
        this.distance = source.distance;
        this.encodedDir = ndir_to_oct_equal_area_snorm(source.dir);
        this.posW = source.posW;
        this.selectionPdf = source.selectionPdf;
        this.Size = source.Size;
        this.jacobianCounterpart = source.jacobianCounterpart;
        this.packedComponents.x = 0u;
        this.packedComponents.y = 0u;
        this.packedComponents.x |= source.LightType & (uint)PackedComponentsMask::LightType;
        this.packedComponents.x |= (source.lastBounceIdx << 2) & (uint)PackedComponentsMask::LastBounceIdx;
        this.packedComponents.x |= (source.firstNonDeltaInteractionIdx << 6) & (uint)PackedComponentsMask::FirstNonDeltaInteractionIdx;
        this.packedComponents.x |= (source.firstReconnectionableBounceIdx << 10) & (uint)PackedComponentsMask::FirstReconnectionableBounceIdx;
        this.packedComponents.x |= (source.age << 14) & (uint)PackedComponentsMask::Age;
        this.packedComponents.x |= ((source.isDistantEmitter ? 1u : 0u) << 22) & (uint)PackedComponentsMask::IsDistantEmitter;
        const uint wlOffset = (uint)(source.wavelength - SpectrumUtils.minWavelength);
        this.packedComponents.x |= (wlOffset << 23) & (uint)PackedComponentsMask::WaveLength;
        this.packedComponents.y |= source.pixel.x & (uint)PackedComponentsMask::PixelX;
        this.packedComponents.y |= (source.pixel.y << 12) & (uint)PackedComponentsMask::PixelY;
    }

    PathReconstructionData unpack() {
        PathReconstructionData result = {};
        result.Le = hwss_t(0.0f);
#if HWSS_SAMPLES == 1
        result.Le[0] = L1;
#endif
#if HWSS_SAMPLES == 2
        result.Le[0] = L1;
        result.Le[1] = L2;
#endif
#if HWSS_SAMPLES == 3
        result.Le[0] = L1;
        result.Le[1] = L2;
        result.Le[2] = L3;
#endif
#if HWSS_SAMPLES == 4
        result.Le[0] = L1;
        result.Le[1] = L2;
        result.Le[2] = L3;
        result.Le[3] = L4;
#endif
        result.pdf = this.pdf;
        result.distance = this.distance;
        result.dir = oct_to_ndir_equal_area_snorm(this.encodedDir);
        result.posW = this.posW;
        result.selectionPdf = this.selectionPdf;
        result.Size = this.Size;
        result.jacobianCounterpart = this.jacobianCounterpart;
        result.LightType = this.packedComponents.x & (uint)PackedComponentsMask::LightType;
        result.lastBounceIdx = (this.packedComponents.x & (uint)PackedComponentsMask::LastBounceIdx) >> 2;
        result.firstNonDeltaInteractionIdx = (this.packedComponents.x & (uint)PackedComponentsMask::FirstNonDeltaInteractionIdx) >> 6;
        result.firstReconnectionableBounceIdx = (this.packedComponents.x & (uint)PackedComponentsMask::FirstReconnectionableBounceIdx) >> 10;
        result.age = (this.packedComponents.x & (uint)PackedComponentsMask::Age) >> 14;
        result.isDistantEmitter = (this.packedComponents.x & (uint)PackedComponentsMask::IsDistantEmitter) != 0;
        const uint wlOffset = (this.packedComponents.x & (uint)PackedComponentsMask::WaveLength) >> 23;
        result.wavelength = wlOffset + SpectrumUtils.minWavelength;
        result.pixel.x = this.packedComponents.y & (uint)PackedComponentsMask::PixelX;
        result.pixel.y = (this.packedComponents.y & (uint)PackedComponentsMask::PixelY) >> 12;
        return result;
    }
};
