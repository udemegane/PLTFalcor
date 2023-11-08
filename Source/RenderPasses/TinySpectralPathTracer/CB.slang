import Rendering.Lights.EmissiveLightSampler;
import Rendering.Lights.EnvMapSampler;

cbuffer CB
{
    uint gFrameCount;
    uint2 gFrameDim;
    EnvMapSampler envMapSampler;
    EmissiveLightSampler emissiveSampler;
}
