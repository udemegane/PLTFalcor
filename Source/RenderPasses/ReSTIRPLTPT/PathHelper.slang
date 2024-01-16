import Utils.HWSS;
import Rendering.Utils.LightsSamplingUtils;
import Rendering.Materials.LobeType;

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

    ////////////////////////////////////
    // Reference to Path-Vertex array //
    ////////////////////////////////////
    uint lastBounceIdx;                 ///< Index of the last bounce of the path.
    int firstDispersiveInteractionIdx;  ///< -1 if no dispersive interaction
    int firstReconnectionableBounceIdx; ///< -1 if no reconnectionable bounce
    float jacobianCounterpart;          ///< Jacobian of the transformation from solid angle to area measure
                                        ///  and the ratio of bsdf sampling pdfs which is needed for PSS ran
                                        ///  -dom-valiable transformation.
    uint2 pixel;                        ///< Pixel coordinates of the shading point for SampleGenerator-Seed.
    uint age;                           ///< Age of the sample, for SG-Seed. This become old when frame changes.
                                        ///  Note: Very careful when using this. SG Seed is important for PSS
                                        ///  random-replay. The seed is exactly the same as the one which was
                                        ///  used to generate the path.

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
        int firstDispersiveInteractionIdx,
        int firstReconnectionableBounceIdx,
        uint2 pixel,
        uint age)
    {
        this.lastBounceIdx = lastBounceIdx;
        this.firstDispersiveInteractionIdx = firstDispersiveInteractionIdx;
        this.firstReconnectionableBounceIdx = firstReconnectionableBounceIdx;
        this.pixel = pixel;
        this.age = age;
    }

    [mutating]
    void setJacobianCounterpart(float jacobianCounterpart)
    {
        this.jacobianCounterpart = jacobianCounterpart;
    }
    // [mutating]
    // void setLightType(SampledLightType lightType)
    // {
    //     packedLightType |= (uint)lightType;
    //     //  packedLightType |= (isDistantEmitter << 31);
    // }

    // [mutating]
    // void setDistantEmitterType(bool isDistantEmitter) {
    //     uint tmp = isDistantEmitter ? 1 : 0;
    //     packedLightType |= (tmp << 31);
    // }

    // bool checkDistantEmitter() { return (packedLightType >> 31) != 0; }

    // SampledLightType getLightType() { return (SampledLightType)(packedLightType & 0x7fffffff); }

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

struct PackedPathReconstructionData
{};
