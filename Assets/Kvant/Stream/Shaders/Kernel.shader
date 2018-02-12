//
// GPGPU kernels for Stream
//
// Texture format:
// .xyz = particle position
// .w   = particle life
//
Shader "Hidden/Kvant/Stream/Kernel"
{
    Properties
    {
        _MainTex     ("-", 2D)     = ""{}
        _EmitterPos  ("-", Vector) = (0, 0, 0, 0)
        _EmitterSize ("-", Vector) = (40, 40, 40, 0)
        _Direction   ("-", Vector) = (0, 0, -1, 0.2)
        _SpeedParams ("-", Vector) = (5, 10, 0, 0)
        _NoiseParams ("-", Vector) = (0.2, 0.1, 1)  // (frequency, amplitude, animation)
        _Config      ("-", Vector) = (1, 2, 0, 1)   // (throttle, life, random seed, dT)
    }

    CGINCLUDE

    #pragma multi_compile NOISE_OFF NOISE_ON

    #include "UnityCG.cginc"
    #include "ClassicNoise3D.cginc"

    sampler2D _MainTex;

    float3 _EmitterPos;
    float3 _EmitterSize;
    float4 _Direction;
    float2 _SpeedParams;
    float4 _NoiseParams;
    float4 _Config;

    // PRNG function.
    float nrand(float2 uv, float salt)
    {
        uv += float2(salt, _Config.z);
        return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
    }

    float negrand(float2 uv){
    	return (uv.x % 2 - 1)*2;
    }

    // Get a new particle.
    float4 new_particle(float2 uv)
    {
        float t = _Time.x;
        float ty = _Time.y;
        float3 p;
        p = float3(nrand(uv, 1), nrand(uv, 2)/2 + 0.2, nrand(uv, 3));

        p = (p - (float3)0.5) * _EmitterSize + _EmitterPos;
        float radius = pow(pow(p.z,2) + pow(p.x,2) + pow(p.y,2) , 0.5);

        // Life duration.
        float l = (radius > 5.0f)? _Config.y * (0.5 + nrand(uv, t + 0)) : 1;

        // Throttling: discard particle emission by adding offset.
        _Config.x = _Config.x/(ty); // decrease throttle by ty/2
        //l = (_Config.x < 0.01)? 0 : l; // decrease life to 0 if throttle is too small
        float4 offs = float4(1e8, 1e8, 1e8, -1e8) * (uv.x > _Config.x);

        return float4(p, l) + offs;
    }

    // Position dependant velocity field.
    float3 get_velocity(float3 p, float2 uv)
    {
    	float ty = _Time.y;
    	float sint = _SinTime.x;
    	float3 v;
        float angle = atan(p.x/p.z);
        float radius = pow(pow(p.z,2) + pow(p.x,2) + pow(p.y,2), 0.5);
        v = (p.z > 0) ? float3(-cos(angle)*radius*0.5, nrand(uv,4)/10 * negrand(uv), sin(angle)*radius*0.5) : float3(cos(angle)*radius*0.5, nrand(uv,4)/10 * negrand(uv), -sin(angle)*radius*0.5);

//        v.x = (radius < 8.0f)? 1 : (radius < 15) ? v.x*5 : v.x;
//        v.z = (radius < 8.0f)? 1 : (radius < 15) ? v.z*5 : v.z;
//        v.y = (radius < 8.0f)? v.y/5 : v.y;

        _SpeedParams.x = (radius < 4.0f)? 0 : 5;
        _SpeedParams.y = (radius < 4.0f)? 0.1 : 10;

        // Force
        float fx,fz;
        if(p.x > 0 && p.z < 0){
        	fx = -p.x;
        	fz = p.z;
        }else if(p.x < 0 && p.z < 0) {
        	fx = p.x;
        	fz = -p.z;
        }else if(p.x < 0 && p.z > 0) {
        	fx = -p.x;
        	fz = p.z;
        }else if(p.x > 0 && p.z > 0) {
        	fx = p.x;
        	fz = -p.z;
        }
        float3 f = float3(fz * 0.8,0,fx * 0.8);


        // Apply the speed parameter.
        v = normalize(v) * lerp(_SpeedParams.x, _SpeedParams.y, nrand(uv, 7));
        //v =  normalize(f)* lerp(_SpeedParams.x, _SpeedParams.y, nrand(uv, 7));

#ifdef NOISE_ON
        // Add noise vector.
        p = (p + _Time.y * _NoiseParams.z) * _NoiseParams.x;
        float nx = cnoise(p + float3(0, 0, 0));
        float ny = cnoise(p + float3(0, 50, 0));
        float nz = cnoise(p + float3(0, 0, 0));
        v += float3(nx, ny, nz) * _NoiseParams.y;
#endif
        return v;
    }

    float3 get_damped_velocity (float3 p, float2 uv) {
    	float ty = _Time.y;
     	float3 v;
        float angle = atan(p.x/p.z);
        float radius = pow(pow(p.z,2) + pow(p.x,2) + pow(p.y,2), 0.5);
        _SpeedParams.x = (radius < 4.0f)? 0 : 5;
        _SpeedParams.y = (radius < 4.0f)? 0.1 : 10;
        radius = radius / (ty + radius*0.5) ;
        v = (p.z > 0) ? float3(-cos(angle)*radius*0.5, nrand(uv,4)/10 * negrand(uv), sin(angle)*radius*0.5) : float3(cos(angle)*radius*0.5, nrand(uv,4)/10 * negrand(uv), -sin(angle)*radius*0.5);

        v = normalize(v) * lerp(_SpeedParams.x, _SpeedParams.y, nrand(uv, 7));
        return v;
    }

    // Pass 0: Initialization
    float4 frag_init(v2f_img i) : SV_Target 
    {
        return new_particle(i.uv);
    }

    // Pass 1: Update
    float4 frag_update(v2f_img i) : SV_Target 
    {
        float4 p = tex2D(_MainTex, i.uv);
        if (p.w > 0)
        {
            float dt = _Config.w;
            float radius = pow(pow(p.z,2) + pow(p.x,2) + pow(p.y,2), 0.5);
            p.xyz = (radius < 10.0f && radius > 2.0f)? p.xyz + get_damped_velocity(p.xyz, i.uv) * dt : p.xyz + get_velocity(p.xyz, i.uv) * dt ; // position
            p.w = (radius > 4.0f)? p.w - dt : 1; // life
            return p;
        }
        else
        {
            return new_particle(i.uv);
        }
    }

    ENDCG

    SubShader
    {
        // Pass 0: Initialization
        Pass
        {
            CGPROGRAM
            #pragma target 3.0
            #pragma vertex vert_img
            #pragma fragment frag_init
            ENDCG
        }
        // Pass 1: Update
        Pass
        {
            CGPROGRAM
            #pragma target 3.0
            #pragma vertex vert_img
            #pragma fragment frag_update
            ENDCG
        }
    }
}
