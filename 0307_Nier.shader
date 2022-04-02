Shader "Unlit/Nier"
{
    Properties
    {
        _BaseColor ("基础颜色", Color) = (1, 1, 1, 1)
        _BaseMap ("基础贴图", 2D) = "white" { }
        [NoScaleOffset]_MaskMap ("MASK贴图", 2D) = "white" { }
        [NoScaleOffset][Normal]_NormalMap ("法线贴图", 2D) = "Bump" { }
        _NormalScale ("法线强度", Range(0.001, 1)) = 1
    }

    HLSLINCLUDE

    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
    #include "Assets/PBR/My_PBR.hlsl"

    ENDHLSL
    
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" }
        HLSLINCLUDE

        CBUFFER_START(UnityPerMaterial)
        float4   _BaseColor;
        float4   _BaseMap_ST;
        float    _NormalScale;

        TEXTURE2D(_BaseMap);       SAMPLER(sampler_BaseMap);
        TEXTURE2D(_MaskMap);       SAMPLER(sampler_MaskMap);
        TEXTURE2D(_NormalMap);     SAMPLER(sampler_NormalMap);

        CBUFFER_END

        struct a2v
        {
            float4 position:     POSITION;
            float4 normal:       NORMAL;
            float2 texCoord:     TEXCOORD;
            float4 tangent:      TANGENT;
            
        };
        struct v2f
        {
            float4 positionCS:   SV_POSITION;
            float2 texcoord:     TEXCOORD0;
            float3 normalWS:     NORMAL;
            float3 tangentWS:    TANGENT;
            float3 bitangentWS:  TEXCOORD1;
            float3 pos:          TEXCOORD2;
        };
        ENDHLSL

        Pass
        {
            Tags { "LightMode" = "UniversalForward" "RenderType" = "Opaque" }
            HLSLPROGRAM

            #pragma target 4.5
            #pragma vertex VERT
            #pragma fragment FRAG

            v2f VERT(a2v i)
            {
                v2f o;
                //转换一堆参数
                o.positionCS   = TransformObjectToHClip(i.position.xyz);//MVP变换
                o.texcoord.xy  = TRANSFORM_TEX(i.texCoord, _BaseMap);//UV
                o.normalWS     = normalize(TransformObjectToWorldNormal(i.normal.xyz));
                o.tangentWS    = normalize(TransformObjectToWorldDir(i.tangent.xyz));
                o.bitangentWS  = cross(o.normalWS, o.tangentWS);
                o.pos          = TransformObjectToWorld(i.position.xyz);
                return o;
            }
            real4 FRAG(v2f i): SV_TARGET
            {
                //前置数据
                Light mainLight = GetMainLight();

                //贴图处理
                float4 pack_normal    =   SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.texcoord);
                float3 unpack_normal  =   UnpackNormalScale(pack_normal, _NormalScale);

                float3 BaseColor      =   _BaseColor; // BaseColor 为 贴图 乘 颜色
                float4 Mask           =   SAMPLE_TEXTURE2D(_MaskMap, sampler_MaskMap, i.texcoord.xy); 

                float  Metallic       =   Mask.r;
                float  AO             =   Mask.g;
                float  smoothness     =   Mask.a;
                //mask里的b通道上是Detail Mask，这里用不着就不管了

                //基础矢量
                float3 position = i.pos;
                float3 T        = normalize(i.tangentWS);
                float3 B        = normalize(i.bitangentWS);
                float3 N        = normalize(unpack_normal.x * _NormalScale * T + unpack_normal.y * _NormalScale * B + unpack_normal.z * i.normalWS);

                float3 L        = normalize(mainLight.direction);
                float3 V        = normalize(_WorldSpaceCameraPos.xyz - position.xyz);
                float3 H        = normalize(V + L);

                float NoL       = max(saturate(dot(N, L)), 0.000001);

                //直接漫反射项
                float3 diffuse     =  BaseColor ;//Lambert Diffuse
                float3 DirectColor =  diffuse * NoL * mainLight.color * AO * AO * (1, 0.88, 0.93) ;

                //间接光漫反射
                float3 SH          = SH_Process(N) * AO * AO;
                //球谐与AO做两个正片叠底

                //return half4(DirectColor + IndirColor, 1.0);
                return half4 ((0.71, 0.71, 0.82) * 0.9 * SH * (1, 0.88, 0.93) + (1, 0.9, 0.75) * 0.85 * DirectColor, 1.0);
                //这个配色好JB难调！
            }
            ENDHLSL

        }

        Pass //阴影Pass
        {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}
            // URP LightMode Tags：
            // Tags{“LightMode” = “XXX”}
            // UniversalForward：前向渲染物件之用
            // ShadowCaster： 投射阴影之用
            // DepthOnly：只用来产生深度图
            // Mata：来用烘焙光照图之用
            // Universal2D ：做2D游戏用的，用来替代前向渲染
            // UniversalGBuffer ： 与延迟渲染相关，Geometry_Buffer（开发中）

            // HLSL数据类型1 – 基础数据
            // bool – true / false.
            // float – 32位浮点数，用在比如世界坐标，纹理坐标，复杂的函数计算
            // half – 16位浮点数，用于短向量、方向、颜色，模型空间位置
            // double – 64位浮点数，不能用于输入输出，要使用double，得声明为一对unit再用asuint把double打包到uint对中，再用asdouble函数解包
            // fixed – 只能用于内建管线，URP不支持，用half替代
            // real – 好像只用于URP，如果平台指定了用half（#define PREFER_HALF 0），否则就是float类型
            // int – 32位有符号整形
            // uint – 32位无符号整形(GLES2不支持，会用int替代)

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull off

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON

            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
    }
}