import Utils.HWSS;
import Rendering.Utils.LightsSamplingUtils;

struct LightSampleSeed
{
    hwss_t Le;      ///< Emitted radiance.
    float pdf;      ///< Pdf with respect to solid angle at the shading point.
    float3 origin;  ///< Ray origin for visibility evaluation (offseted to avoid self-intersection).
    float distance; ///< Ray distance for visibility evaluation (shortened to avoid self-intersection).
    float3 dir;     ///< Ray direction for visibility evaluation (normalized).
    float3 posW;    ///< Shading point position in world space.
    float wavelength;
    uint packedLightType;
    float selectionPdf;
    float Size;      ///< Omega or A
    float misWeight; ///< MIS weight of NEE and BSDF sampling

    [mutating]
    void setLightType(SampledLightType lightType)
    {
        packedLightType |= (uint)lightType;
        //  packedLightType |= (isDistantEmitter << 31);
    }

    [mutating]
    void setDistantEmitterType(bool isDistantEmitter) {
        uint tmp = isDistantEmitter ? 1 : 0;
        packedLightType |= (tmp << 31);
    }

    bool checkDistantEmitter() { return (packedLightType >> 31) != 0; }

    SampledLightType getLightType() { return (SampledLightType)(packedLightType & 0x7fffffff); }
};
