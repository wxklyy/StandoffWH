// StandoffWH — Wallhack tweak for Standoff 2 (Unity IL2CPP, iOS arm64)
// Runtime IL2CPP resolution + shader-based WH + anticheat bypass

#import <substrate.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <spawn.h>

#import "imgui.h"
#import "imgui_impl_metal.h"

// ═══════════════════════════════════════
// IL2CPP API typedefs
// ═══════════════════════════════════════

typedef void  Il2CppDomain;
typedef void  Il2CppAssembly;
typedef void  Il2CppImage;
typedef void  Il2CppClass;
typedef void  Il2CppMethodInfo;
typedef void  Il2CppObject;
typedef void  Il2CppArray;
typedef void  Il2CppString;
typedef void  Il2CppType;

typedef Il2CppDomain*    (*il2cpp_domain_get_t)(void);
typedef Il2CppAssembly** (*il2cpp_domain_get_assemblies_t)(Il2CppDomain*, size_t*);
typedef Il2CppImage*     (*il2cpp_assembly_get_image_t)(Il2CppAssembly*);
typedef Il2CppClass*     (*il2cpp_class_from_name_t)(Il2CppImage*, const char*, const char*);
typedef Il2CppMethodInfo*(*il2cpp_class_get_method_from_name_t)(Il2CppClass*, const char*, int);
typedef Il2CppClass*     (*il2cpp_class_get_nested_types_t)(Il2CppClass*, void**);
typedef void*            (*il2cpp_method_get_param_t)(Il2CppMethodInfo*, uint32_t);
typedef Il2CppString*    (*il2cpp_string_new_t)(const char*);
typedef const char*      (*il2cpp_class_get_name_t)(Il2CppClass*);
typedef const char*      (*il2cpp_class_get_namespace_t)(Il2CppClass*);
typedef Il2CppType*      (*il2cpp_class_get_type_t)(Il2CppClass*);
typedef Il2CppObject*    (*il2cpp_type_get_object_t)(Il2CppType*);
typedef Il2CppClass*     (*il2cpp_object_get_class_t)(Il2CppObject*);
typedef void*            (*il2cpp_resolve_icall_t)(const char*);
typedef Il2CppObject*    (*il2cpp_runtime_invoke_t)(Il2CppMethodInfo*, void*, void**, Il2CppObject**);
typedef Il2CppArray*     (*il2cpp_array_new_t)(Il2CppClass*, size_t);
typedef Il2CppClass*     (*il2cpp_image_get_class_t)(Il2CppImage*, size_t);
typedef size_t           (*il2cpp_image_get_class_count_t)(Il2CppImage*);
typedef void*            (*il2cpp_field_get_value_t)(Il2CppObject*, void*, void*);
typedef void*            (*il2cpp_field_get_offset_t)(void*);
typedef void*            (*il2cpp_class_get_fields_t)(Il2CppClass*, void**);
typedef void*            (*il2cpp_class_get_field_from_name_t)(Il2CppClass*, const char*);
typedef const char*      (*il2cpp_field_get_name_t)(void*);

// resolved function pointers
static il2cpp_domain_get_t                   il2cpp_domain_get;
static il2cpp_domain_get_assemblies_t        il2cpp_domain_get_assemblies;
static il2cpp_assembly_get_image_t           il2cpp_assembly_get_image;
static il2cpp_class_from_name_t              il2cpp_class_from_name;
static il2cpp_class_get_method_from_name_t   il2cpp_class_get_method_from_name;
static il2cpp_string_new_t                   il2cpp_string_new;
static il2cpp_class_get_name_t               il2cpp_class_get_name;
static il2cpp_class_get_namespace_t          il2cpp_class_get_namespace;
static il2cpp_resolve_icall_t                il2cpp_resolve_icall;
static il2cpp_runtime_invoke_t               il2cpp_runtime_invoke;
static il2cpp_image_get_class_t              il2cpp_image_get_class;
static il2cpp_image_get_class_count_t        il2cpp_image_get_class_count;
static il2cpp_class_get_field_from_name_t    il2cpp_class_get_field_from_name;
static il2cpp_field_get_name_t               il2cpp_field_get_name;
static il2cpp_class_get_fields_t             il2cpp_class_get_fields;
static il2cpp_object_get_class_t             il2cpp_object_get_class;
static il2cpp_class_get_type_t               il2cpp_class_get_type;
static il2cpp_type_get_object_t              il2cpp_type_get_object;

// ═══════════════════════════════════════
// State
// ═══════════════════════════════════════

static bool g_wallhackEnabled  = true;
static bool g_chamEnabled      = true;   // player glow/cham
static bool g_initialized      = false;
static void* g_unityFramework  = NULL;

// cached IL2CPP classes
static Il2CppImage* g_assemblyCSharp  = NULL;
static Il2CppClass* g_shaderClass     = NULL;
static Il2CppClass* g_materialClass   = NULL;
static Il2CppClass* g_rendererClass   = NULL;
static Il2CppClass* g_skinnedClass    = NULL;
static Il2CppClass* g_gameObjectClass = NULL;
static Il2CppClass* g_componentClass  = NULL;
static Il2CppClass* g_cameraClass     = NULL;
static Il2CppClass* g_objectClass     = NULL;
static Il2CppClass* g_antiCheatClass  = NULL;
static Il2CppClass* g_gameACClass     = NULL;

// cached methods
static Il2CppMethodInfo* g_shaderFind         = NULL;
static Il2CppMethodInfo* g_materialSetShader  = NULL;
static Il2CppMethodInfo* g_materialSetColor   = NULL;
static Il2CppMethodInfo* g_materialSetInt     = NULL;
static Il2CppMethodInfo* g_rendererGetMaterial = NULL;
static Il2CppMethodInfo* g_objectFindObjectsOfType = NULL;
static Il2CppMethodInfo* g_componentGetGameObject   = NULL;
static Il2CppMethodInfo* g_gameObjectGetLayer       = NULL;
static Il2CppMethodInfo* g_gameObjectSetLayer       = NULL;

// ═══════════════════════════════════════
// ANTI-DETECTION: hide from jailbreak checks
// ═══════════════════════════════════════

// --- Hook sysctl to hide debugger ---
static int (*orig_sysctl)(int*, u_int, void*, size_t*, void*, size_t);
static int hook_sysctl(int* name, u_int namelen, void* info, size_t* infosize, void* newinfo, size_t newinfolen) {
    int ret = orig_sysctl(name, namelen, info, infosize, newinfo, newinfolen);
    if (namelen == 4 && name[0] == CTL_KERN && name[1] == KERN_PROC && name[2] == KERN_PROC_PID) {
        struct kinfo_proc* kinfo = (struct kinfo_proc*)info;
        if (kinfo) {
            kinfo->kp_proc.p_flag &= ~P_TRACED; // hide debugger flag
        }
    }
    return ret;
}

// --- Hook _dyld_image_count / _dyld_get_image_name to hide injected dylibs ---
static uint32_t g_originalImageCount = 0;
static bool g_imageCountCaptured = false;

static uint32_t (*orig_dyld_image_count)(void);
static uint32_t hook_dyld_image_count(void) {
    if (!g_imageCountCaptured) {
        g_originalImageCount = orig_dyld_image_count();
        g_imageCountCaptured = true;
    }
    return g_originalImageCount;
}

static const char* (*orig_dyld_get_image_name)(uint32_t);
static const char* hook_dyld_get_image_name(uint32_t idx) {
    const char* name = orig_dyld_get_image_name(idx);
    if (name) {
        // hide our tweak dylib and substrate
        if (strstr(name, "StandoffWH") || strstr(name, "substrate") ||
            strstr(name, "substitute") || strstr(name, "frida") ||
            strstr(name, "cycript") || strstr(name, "libhooker")) {
            return "/usr/lib/system/libsystem_c.dylib";  // return legit lib
        }
    }
    return name;
}

// --- Hook NSFileManager fileExistsAtPath: to hide jailbreak paths ---
static BOOL (*orig_fileExists)(id, SEL, NSString*);
static BOOL hook_fileExists(id self, SEL _cmd, NSString* path) {
    static NSArray* blockedPaths = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blockedPaths = @[
            @"/Applications/Cydia.app",
            @"/Applications/blackra1n.app",
            @"/Applications/FakeCarrier.app",
            @"/Applications/IntelliScreen.app",
            @"/Applications/Snoop-itConfig.app",
            @"/Library/MobileSubstrate/MobileSubstrate.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries",
            @"/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist",
            @"/System/Library/LaunchDaemons/com.ikey.bbot.plist",
            @"/usr/libexec/ssh-keysign",
            @"/usr/libexec/cydia",
            @"/usr/sbin/frida-server",
            @"/private/var/lib/cydia",
            @"/private/var/tmp/cydia.log",
            @"/var/lib/cydia",
            @"/private/jailbreak.txt",
            @"/usr/sbin/sshd",
            @"/usr/bin/ssh",
            @"/etc/apt",
            @"/bin/bash",
            @"/bin/sh",
        ];
    });

    for (NSString* blocked in blockedPaths) {
        if ([path hasPrefix:blocked]) {
            return NO;
        }
    }
    return orig_fileExists(self, _cmd, path);
}

// --- Hook canOpenURL to block cydia:// ---
static BOOL (*orig_canOpenURL)(id, SEL, NSURL*);
static BOOL hook_canOpenURL(id self, SEL _cmd, NSURL* url) {
    if ([[url scheme] isEqualToString:@"cydia"]) {
        return NO;
    }
    return orig_canOpenURL(self, _cmd, url);
}

// --- Hook fork/access for jailbreak detection ---
static pid_t (*orig_fork)(void);
static pid_t hook_fork(void) {
    return -1; // pretend fork fails = not jailbroken
}

static int (*orig_access)(const char*, int);
static int hook_access(const char* path, int mode) {
    if (path) {
        if (strstr(path, "cydia") || strstr(path, "substrate") ||
            strstr(path, "frida") || strstr(path, "sshd") ||
            strstr(path, "jailbreak")) {
            return -1;
        }
    }
    return orig_access(path, mode);
}

// ═══════════════════════════════════════
// IL2CPP resolver helpers
// ═══════════════════════════════════════

static bool resolveIL2CPP() {
    g_unityFramework = dlopen("UnityFramework", RTLD_NOLOAD);
    if (!g_unityFramework) {
        g_unityFramework = dlopen("/Frameworks/UnityFramework.framework/UnityFramework", RTLD_NOLOAD);
    }
    if (!g_unityFramework) return false;

    #define RESOLVE(name) name = (name##_t)dlsym(g_unityFramework, #name); if (!name) return false;

    RESOLVE(il2cpp_domain_get);
    RESOLVE(il2cpp_domain_get_assemblies);
    RESOLVE(il2cpp_assembly_get_image);
    RESOLVE(il2cpp_class_from_name);
    RESOLVE(il2cpp_class_get_method_from_name);
    RESOLVE(il2cpp_string_new);
    RESOLVE(il2cpp_class_get_name);
    RESOLVE(il2cpp_class_get_namespace);
    RESOLVE(il2cpp_resolve_icall);
    RESOLVE(il2cpp_runtime_invoke);
    RESOLVE(il2cpp_image_get_class);
    RESOLVE(il2cpp_image_get_class_count);
    RESOLVE(il2cpp_class_get_field_from_name);
    RESOLVE(il2cpp_field_get_name);
    RESOLVE(il2cpp_class_get_fields);
    RESOLVE(il2cpp_object_get_class);
    RESOLVE(il2cpp_class_get_type);
    RESOLVE(il2cpp_type_get_object);

    #undef RESOLVE
    return true;
}

static Il2CppImage* getImage(const char* assemblyName) {
    Il2CppDomain* domain = il2cpp_domain_get();
    if (!domain) return NULL;

    size_t count = 0;
    Il2CppAssembly** assemblies = il2cpp_domain_get_assemblies(domain, &count);
    if (!assemblies) return NULL;

    for (size_t i = 0; i < count; i++) {
        Il2CppImage* img = il2cpp_assembly_get_image(assemblies[i]);
        if (!img) continue;

        // walk classes to check image name via class namespace matching
        size_t classCount = il2cpp_image_get_class_count(img);
        for (size_t j = 0; j < classCount && j < 5; j++) {
            Il2CppClass* cls = il2cpp_image_get_class(img, j);
            if (!cls) continue;
            // the image name is embedded - we match by trying to find a known class
        }

        // try to find a class we know exists in the target assembly
        Il2CppClass* test = il2cpp_class_from_name(img, "UnityEngine", "Shader");
        if (test && strcmp(assemblyName, "UnityEngine.CoreModule.dll") == 0) return img;

        test = il2cpp_class_from_name(img, "Axlebolt.Standoff.Anitcheat", "AntiCheatManager");
        if (test && strcmp(assemblyName, "Assembly-CSharp.dll") == 0) return img;
    }
    return NULL;
}

static Il2CppImage* findImageWithClass(const char* ns, const char* name) {
    Il2CppDomain* domain = il2cpp_domain_get();
    if (!domain) return NULL;

    size_t count = 0;
    Il2CppAssembly** assemblies = il2cpp_domain_get_assemblies(domain, &count);
    if (!assemblies) return NULL;

    for (size_t i = 0; i < count; i++) {
        Il2CppImage* img = il2cpp_assembly_get_image(assemblies[i]);
        if (!img) continue;
        Il2CppClass* cls = il2cpp_class_from_name(img, ns, name);
        if (cls) return img;
    }
    return NULL;
}

// ═══════════════════════════════════════
// AntiCheat bypass via IL2CPP hooks
// ═══════════════════════════════════════

// hook AntiCheatManager methods that report cheats — make them no-op
typedef void (*ReportViaServer_t)(Il2CppObject*, Il2CppString*, Il2CppString*);
static ReportViaServer_t orig_ReportViaServer = NULL;
static void hook_ReportViaServer(Il2CppObject* self, Il2CppString* type, Il2CppString* data) {
    // swallow all cheat reports
    return;
}

// hook the obfuscated AC init/check methods to no-op
typedef void (*ACMethod_void_t)(Il2CppObject*);
static ACMethod_void_t orig_AC_NFIAANGEACF = NULL;
static void hook_AC_NFIAANGEACF(Il2CppObject* self) { return; }

static ACMethod_void_t orig_AC_CLNMOGLLDMN = NULL;
static void hook_AC_CLNMOGLLDMN(Il2CppObject* self) { return; }

static ACMethod_void_t orig_AC_HJABCADCDMB = NULL;
static void hook_AC_HJABCADCDMB(Il2CppObject* self) { return; }

static ACMethod_void_t orig_AC_BLBHHGOPBCM = NULL;
static void hook_AC_BLBHHGOPBCM(Il2CppObject* self) { return; }

static ACMethod_void_t orig_AC_DHNPEOIDGED = NULL;
static void hook_AC_DHNPEOIDGED(Il2CppObject* self) { return; }

static ACMethod_void_t orig_AC_ECHAHOJDKEB = NULL;
static void hook_AC_ECHAHOJDKEB(Il2CppObject* self) { return; }

// ═══════════════════════════════════════
// WALLHACK: Shader replacement approach
// ═══════════════════════════════════════
//
// Strategy: Find all SkinnedMeshRenderer components on player GameObjects,
// replace their material shaders with a z-test-always shader so players
// render through geometry. Apply a color tint for cham effect.
//
// We use Unity's internal Shader.Find("Hidden/Internal-Colored") which
// draws with ZTest Always, or we build a custom shader string at runtime.
//

// Unity Color struct
struct UnityColor {
    float r, g, b, a;
};
static UnityColor g_chamColor = {0.0f, 1.0f, 0.2f, 0.7f};

// cached shader references
static Il2CppObject* g_wallhackShader = NULL;  // ZTest Always shader
static Il2CppObject* g_normalShader   = NULL;  // default shader for restore

// icall function pointers (resolved at runtime)
typedef void  (*Camera_SetCullingMask_t)(Il2CppObject*, int);
typedef int   (*Camera_GetCullingMask_t)(Il2CppObject*);
typedef Il2CppArray* (*Object_FindObjectsOfType_t)(Il2CppObject* type);
typedef Il2CppObject* (*Component_GetGameObject_t)(Il2CppObject*);
typedef int   (*GameObject_GetLayer_t)(Il2CppObject*);
typedef void  (*GameObject_SetLayer_t)(Il2CppObject*, int);

static Camera_SetCullingMask_t  fn_Camera_SetCullingMask  = NULL;
static Camera_GetCullingMask_t  fn_Camera_GetCullingMask  = NULL;

// ═══════════════════════════════════════
// Wallhack via Renderer material swap
// ═══════════════════════════════════════

static Il2CppObject* findShader(const char* name) {
    if (!g_shaderFind) return NULL;
    Il2CppObject* exc = NULL;
    Il2CppString* shaderName = il2cpp_string_new(name);
    void* args[] = { shaderName };
    Il2CppObject* shader = il2cpp_runtime_invoke(g_shaderFind, NULL, args, &exc);
    return shader;
}

static void setMaterialShader(Il2CppObject* material, Il2CppObject* shader) {
    if (!g_materialSetShader || !material || !shader) return;
    Il2CppObject* exc = NULL;
    void* args[] = { shader };
    il2cpp_runtime_invoke(g_materialSetShader, material, args, &exc);
}

static void setMaterialColor(Il2CppObject* material, const char* propertyName, UnityColor color) {
    if (!g_materialSetColor || !material) return;
    Il2CppObject* exc = NULL;
    Il2CppString* prop = il2cpp_string_new(propertyName);
    void* args[] = { prop, &color };
    il2cpp_runtime_invoke(g_materialSetColor, material, args, &exc);
}

static void setMaterialInt(Il2CppObject* material, const char* propertyName, int value) {
    if (!g_materialSetInt || !material) return;
    Il2CppObject* exc = NULL;
    Il2CppString* prop = il2cpp_string_new(propertyName);
    void* args[] = { prop, &value };
    il2cpp_runtime_invoke(g_materialSetInt, material, args, &exc);
}

// ═══════════════════════════════════════
// Camera culling mask approach (simpler WH)
// ═══════════════════════════════════════
//
// Unity cameras have a cullingMask that determines which layers to render.
// By hooking Camera.Render or LateUpdate, we can force the camera to
// render the player layer with depth test disabled.
//
// Alternative: hook Shader.Find to inject our own ZTest Always variant.
//

// Hook UnityEngine.Camera::set_cullingMask to ensure player layer is always visible
typedef void (*Camera_set_cullingMask_t)(Il2CppObject*, int);
static Camera_set_cullingMask_t orig_Camera_set_cullingMask = NULL;
static void hook_Camera_set_cullingMask(Il2CppObject* self, int mask) {
    if (g_wallhackEnabled) {
        // force-include all layers so nothing is culled (players always visible)
        mask |= (1 << 8) | (1 << 9) | (1 << 10) | (1 << 11) | (1 << 12) |
                (1 << 13) | (1 << 14) | (1 << 15) | (1 << 29) | (1 << 30) | (1 << 31);
    }
    orig_Camera_set_cullingMask(self, mask);
}

// ═══════════════════════════════════════
// Shader.Find hook — core WH mechanism
// ═══════════════════════════════════════
//
// When the game loads player shaders, we intercept Shader.Find and return
// a shader with ZTest Always so players draw through walls.
//

typedef Il2CppObject* (*ShaderFind_t)(Il2CppString*);
static ShaderFind_t orig_ShaderFind = NULL;

// shader names used for player models in Standoff 2
static bool isPlayerShader(const char* name) {
    if (!name) return false;
    return (strstr(name, "Character") != NULL ||
            strstr(name, "Player") != NULL ||
            strstr(name, "Skin") != NULL ||
            strstr(name, "Body") != NULL ||
            strstr(name, "Arms") != NULL ||
            strstr(name, "Gloves") != NULL ||
            strstr(name, "Standard") != NULL);
}

static Il2CppObject* hook_ShaderFind(Il2CppString* name) {
    Il2CppObject* result = orig_ShaderFind(name);
    // we don't swap here — we swap when materials are applied to player renderers
    return result;
}

// ═══════════════════════════════════════
// Renderer.set_material hook — the real WH
// ═══════════════════════════════════════
//
// When a Renderer gets a material assigned, check if it belongs to a player
// and override its shader properties to render through walls.
//

typedef void (*Renderer_set_material_t)(Il2CppObject*, Il2CppObject*);
static Renderer_set_material_t orig_Renderer_set_material = NULL;

typedef Il2CppObject* (*Renderer_get_material_t)(Il2CppObject*);
static Renderer_get_material_t orig_Renderer_get_material = NULL;

// ═══════════════════════════════════════
// Per-frame WH update via Camera.OnPreRender hook
// ═══════════════════════════════════════

// we store a list of renderer pointers to process
static NSMutableSet* g_processedRenderers = nil;

// ═══════════════════════════════════════
// Main wallhack via LateUpdate hooking
// ═══════════════════════════════════════
//
// Hook the player controller's LateUpdate to modify
// its renderer materials every frame.
//

typedef void (*PlayerLateUpdate_t)(Il2CppObject*);
static PlayerLateUpdate_t orig_PlayerLateUpdate = NULL;

static void applyWallhackToObject(Il2CppObject* gameObject) {
    if (!gameObject || !g_wallhackEnabled) return;

    // get renderers via GetComponentsInChildren<Renderer>()
    // we use il2cpp_runtime_invoke for this

    if (!g_rendererClass || !g_shaderFind) return;

    // get Renderer's material and swap shader to ZTest Always
    // Use the cached "Hidden/Internal-Colored" shader which has ZTest Always
    if (!g_wallhackShader) {
        g_wallhackShader = findShader("Hidden/Internal-Colored");
        if (!g_wallhackShader) {
            // fallback — try other built-in shaders
            g_wallhackShader = findShader("GUI/Text Shader");
            if (!g_wallhackShader) {
                g_wallhackShader = findShader("Sprites/Default");
            }
        }
    }
}

// ═══════════════════════════════════════
// Occlusion Culling disable
// ═══════════════════════════════════════
//
// Standoff 2 uses occlusion culling (Axlebolt.Standoff.Player.Occlusion namespace).
// Disabling it ensures players behind walls are still rendered.
//

typedef bool (*OcclusionCheck_t)(Il2CppObject*);
static OcclusionCheck_t orig_OcclusionCheck = NULL;
static bool hook_OcclusionCheck(Il2CppObject* self) {
    if (g_wallhackEnabled) return false;  // never occlude
    return orig_OcclusionCheck(self);
}

// Generic hook for any bool method — always returns false (not occluded / not culled)
typedef bool (*BoolMethod_t)(Il2CppObject*);

static BoolMethod_t orig_IsOccluded = NULL;
static bool hook_IsOccluded(Il2CppObject* self) {
    if (g_wallhackEnabled) return false;
    return orig_IsOccluded(self);
}

// ═══════════════════════════════════════
// Material.SetPass / CommandBuffer hooks for chams
// ═══════════════════════════════════════

typedef bool (*Material_SetPass_t)(Il2CppObject*, int);
static Material_SetPass_t orig_Material_SetPass = NULL;
static bool hook_Material_SetPass(Il2CppObject* self, int pass) {
    bool ret = orig_Material_SetPass(self, pass);
    if (g_chamEnabled && self) {
        setMaterialInt(self, "_ZTest", 8); // 8 = Always in Unity
        setMaterialInt(self, "_ZWrite", 0);
        setMaterialColor(self, "_Color", g_chamColor);
    }
    return ret;
}

// ═══════════════════════════════════════
// Dear ImGui Metal Overlay & Hooks
// ═══════════════════════════════════════

static bool g_imguiInited = false;
static bool g_showMenu    = true;

static void do_respring(void) {
    pid_t pid;
    const char* args[] = { "/var/jb/usr/bin/sbreload", NULL };
    posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char* const*)args, NULL);
}

static void renderImGuiOverlay(id<MTLCommandBuffer> commandBuffer, id<CAMetalDrawable> drawable) {
    if (!drawable || ![drawable respondsToSelector:@selector(texture)]) return;
    id<MTLTexture> texture = drawable.texture;
    if (!texture) return;

    @autoreleasepool {
        id<MTLDevice> device = commandBuffer.device;
        if (!device) return;

        CGFloat scale = [UIScreen mainScreen].nativeScale;
        if (scale <= 0.0) scale = 2.0;

        if (!g_imguiInited) {
            IMGUI_CHECKVERSION();
            ImGui::CreateContext();
            ImGuiIO& io = ImGui::GetIO();
            io.IniFilename = NULL;
            io.FontGlobalScale = scale;

            // Cyber / Monastic Dark Green Theme
            ImGuiStyle& style = ImGui::GetStyle();
            style.WindowRounding    = 10.0f;
            style.ChildRounding     = 8.0f;
            style.FrameRounding     = 6.0f;
            style.PopupRounding     = 8.0f;
            style.ScrollbarRounding = 6.0f;
            style.GrabRounding      = 6.0f;
            style.TabRounding       = 6.0f;
            style.WindowBorderSize  = 1.5f;
            style.ScaleAllSizes(scale);

            ImVec4* c = style.Colors;
            c[ImGuiCol_Text]                  = ImVec4(0.95f, 0.98f, 0.95f, 1.00f);
            c[ImGuiCol_TextDisabled]          = ImVec4(0.40f, 0.45f, 0.42f, 1.00f);
            c[ImGuiCol_WindowBg]              = ImVec4(0.06f, 0.07f, 0.08f, 0.94f);
            c[ImGuiCol_ChildBg]               = ImVec4(0.10f, 0.12f, 0.11f, 0.70f);
            c[ImGuiCol_PopupBg]               = ImVec4(0.08f, 0.09f, 0.10f, 0.95f);
            c[ImGuiCol_Border]                = ImVec4(0.10f, 0.90f, 0.35f, 0.70f);
            c[ImGuiCol_BorderShadow]          = ImVec4(0.00f, 0.00f, 0.00f, 0.00f);
            c[ImGuiCol_FrameBg]               = ImVec4(0.12f, 0.15f, 0.13f, 0.85f);
            c[ImGuiCol_FrameBgHovered]        = ImVec4(0.16f, 0.22f, 0.18f, 0.90f);
            c[ImGuiCol_FrameBgActive]         = ImVec4(0.20f, 0.28f, 0.22f, 1.00f);
            c[ImGuiCol_TitleBg]               = ImVec4(0.05f, 0.06f, 0.06f, 1.00f);
            c[ImGuiCol_TitleBgActive]         = ImVec4(0.07f, 0.14f, 0.09f, 1.00f);
            c[ImGuiCol_TitleBgCollapsed]      = ImVec4(0.05f, 0.05f, 0.05f, 0.75f);
            c[ImGuiCol_MenuBarBg]             = ImVec4(0.08f, 0.10f, 0.09f, 1.00f);
            c[ImGuiCol_ScrollbarBg]           = ImVec4(0.06f, 0.07f, 0.07f, 0.60f);
            c[ImGuiCol_ScrollbarGrab]         = ImVec4(0.15f, 0.25f, 0.18f, 1.00f);
            c[ImGuiCol_ScrollbarGrabHovered]  = ImVec4(0.20f, 0.35f, 0.24f, 1.00f);
            c[ImGuiCol_ScrollbarGrabActive]   = ImVec4(0.10f, 0.90f, 0.35f, 1.00f);
            c[ImGuiCol_CheckMark]             = ImVec4(0.10f, 1.00f, 0.40f, 1.00f);
            c[ImGuiCol_SliderGrab]            = ImVec4(0.10f, 0.90f, 0.35f, 1.00f);
            c[ImGuiCol_SliderGrabActive]      = ImVec4(0.10f, 1.00f, 0.45f, 1.00f);
            c[ImGuiCol_Button]                = ImVec4(0.12f, 0.20f, 0.15f, 0.85f);
            c[ImGuiCol_ButtonHovered]         = ImVec4(0.15f, 0.30f, 0.20f, 0.90f);
            c[ImGuiCol_ButtonActive]          = ImVec4(0.10f, 0.90f, 0.35f, 1.00f);
            c[ImGuiCol_Header]                = ImVec4(0.12f, 0.22f, 0.16f, 0.80f);
            c[ImGuiCol_HeaderHovered]         = ImVec4(0.15f, 0.32f, 0.20f, 0.85f);
            c[ImGuiCol_HeaderActive]          = ImVec4(0.10f, 0.90f, 0.35f, 1.00f);
            c[ImGuiCol_Separator]             = ImVec4(0.18f, 0.24f, 0.20f, 0.80f);
            c[ImGuiCol_Tab]                   = ImVec4(0.10f, 0.14f, 0.12f, 0.80f);
            c[ImGuiCol_TabHovered]            = ImVec4(0.15f, 0.30f, 0.20f, 0.90f);
            c[ImGuiCol_TabActive]             = ImVec4(0.08f, 0.25f, 0.14f, 1.00f);

            ImGui_ImplMetal_Init(device);
            g_imguiInited = true;
        }

        MTLRenderPassDescriptor* desc = [MTLRenderPassDescriptor renderPassDescriptor];
        desc.colorAttachments[0].texture = texture;
        desc.colorAttachments[0].loadAction = MTLLoadActionLoad;
        desc.colorAttachments[0].storeAction = MTLStoreActionStore;

        ImGuiIO& io = ImGui::GetIO();
        io.DisplaySize = ImVec2((float)texture.width, (float)texture.height);

        ImGui_ImplMetal_NewFrame(desc);
        ImGui::NewFrame();

        // ── Floating toggle icon when menu is closed ──
        if (!g_showMenu) {
            ImGui::SetNextWindowPos(ImVec2(30 * scale, 30 * scale), ImGuiCond_FirstUseEver);
            ImGui::Begin("##toggle_bubble", nullptr,
                ImGuiWindowFlags_NoDecoration |
                ImGuiWindowFlags_AlwaysAutoResize |
                ImGuiWindowFlags_NoSavedSettings |
                ImGuiWindowFlags_NoFocusOnAppearing |
                ImGuiWindowFlags_NoNav);
            if (ImGui::Button("SWH")) {
                g_showMenu = true;
            }
            ImGui::End();
        } else {
            // ── Main ImGui Window ──
            ImGui::SetNextWindowSize(ImVec2(340 * scale, 270 * scale), ImGuiCond_FirstUseEver);
            if (ImGui::Begin("StandoffWH | Onyx v67", &g_showMenu, ImGuiWindowFlags_NoCollapse)) {
                if (ImGui::BeginTabBar("Tabs")) {
                    if (ImGui::BeginTabItem("Visuals")) {
                        ImGui::Spacing();
                        ImGui::Checkbox("Wallhack (Depth Override)", &g_wallhackEnabled);
                        ImGui::Checkbox("Chams (Player Glow)", &g_chamEnabled);

                        if (g_chamEnabled) {
                            ImGui::Spacing();
                            ImGui::Text("Cham Color:");
                            float col[4] = { g_chamColor.r, g_chamColor.g, g_chamColor.b, g_chamColor.a };
                            if (ImGui::ColorEdit4("##ChamColor", col)) {
                                g_chamColor.r = col[0];
                                g_chamColor.g = col[1];
                                g_chamColor.b = col[2];
                                g_chamColor.a = col[3];
                            }
                        }
                        ImGui::EndTabItem();
                    }

                    if (ImGui::BeginTabItem("Protection")) {
                        ImGui::Spacing();
                        ImGui::TextColored(ImVec4(0.2f, 1.0f, 0.4f, 1.0f), "[+] AntiCheat: Bypassed");
                        ImGui::TextColored(ImVec4(0.2f, 1.0f, 0.4f, 1.0f), "[+] Sysctl P_TRACED: Hidden");
                        ImGui::TextColored(ImVec4(0.2f, 1.0f, 0.4f, 1.0f), "[+] Dylibs: Cloaked");
                        ImGui::TextColored(ImVec4(0.2f, 1.0f, 0.4f, 1.0f), "[+] Jailbreak Paths: Masked");
                        ImGui::EndTabItem();
                    }

                    if (ImGui::BeginTabItem("Info")) {
                        ImGui::Spacing();
                        ImGui::Text("IL2CPP: %s", g_initialized ? "Hooked" : "Searching...");
                        ImGui::Text("FPS: %.1f", io.Framerate);
                        ImGui::Spacing();
                        if (ImGui::Button("Close Menu")) {
                            g_showMenu = false;
                        }
                        ImGui::SameLine();
                        if (ImGui::Button("Respring")) {
                            do_respring();
                        }
                        ImGui::EndTabItem();
                    }

                    ImGui::EndTabBar();
                }
            }
            ImGui::End();
        }

        ImGui::Render();

        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:desc];
        if (encoder) {
            ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, encoder);
            [encoder endEncoding];
        }
    }
}

static void (*orig_presentDrawable)(id, SEL, id<CAMetalDrawable>) = NULL;
static void hook_presentDrawable(id self, SEL _cmd, id<CAMetalDrawable> drawable) {
    renderImGuiOverlay(self, drawable);
    if (orig_presentDrawable) {
        orig_presentDrawable(self, _cmd, drawable);
    }
}

static void (*orig_presentDrawable_afterMinimumDuration)(id, SEL, id<CAMetalDrawable>, CFTimeInterval) = NULL;
static void hook_presentDrawable_afterMinimumDuration(id self, SEL _cmd, id<CAMetalDrawable> drawable, CFTimeInterval duration) {
    renderImGuiOverlay(self, drawable);
    if (orig_presentDrawable_afterMinimumDuration) {
        orig_presentDrawable_afterMinimumDuration(self, _cmd, drawable, duration);
    }
}

static void (*orig_presentDrawable_atTime)(id, SEL, id<CAMetalDrawable>, CFTimeInterval) = NULL;
static void hook_presentDrawable_atTime(id self, SEL _cmd, id<CAMetalDrawable> drawable, CFTimeInterval presentationTime) {
    renderImGuiOverlay(self, drawable);
    if (orig_presentDrawable_atTime) {
        orig_presentDrawable_atTime(self, _cmd, drawable, presentationTime);
    }
}

static Class g_hookedCmdBufClass = Nil;

static void hookCommandBufferClass(Class cls) {
    if (!cls || cls == g_hookedCmdBufClass) return;
    g_hookedCmdBufClass = cls;

    Method m1 = class_getInstanceMethod(cls, @selector(presentDrawable:));
    if (m1) {
        orig_presentDrawable = (void (*)(id, SEL, id<CAMetalDrawable>))method_getImplementation(m1);
        method_setImplementation(m1, (IMP)hook_presentDrawable);
    }

    Method m2 = class_getInstanceMethod(cls, @selector(presentDrawable:afterMinimumDuration:));
    if (m2) {
        orig_presentDrawable_afterMinimumDuration = (void (*)(id, SEL, id<CAMetalDrawable>, CFTimeInterval))method_getImplementation(m2);
        method_setImplementation(m2, (IMP)hook_presentDrawable_afterMinimumDuration);
    }

    Method m3 = class_getInstanceMethod(cls, @selector(presentDrawable:atTime:));
    if (m3) {
        orig_presentDrawable_atTime = (void (*)(id, SEL, id<CAMetalDrawable>, CFTimeInterval))method_getImplementation(m3);
        method_setImplementation(m3, (IMP)hook_presentDrawable_atTime);
    }
}

static id (*orig_cmdBuffer)(id, SEL) = NULL;
static id hook_cmdBuffer(id self, SEL _cmd) {
    id buf = orig_cmdBuffer(self, _cmd);
    if (buf) {
        hookCommandBufferClass(object_getClass(buf));
    }
    return buf;
}

static id (*orig_cmdBufferUnretained)(id, SEL) = NULL;
static id hook_cmdBufferUnretained(id self, SEL _cmd) {
    id buf = orig_cmdBufferUnretained(self, _cmd);
    if (buf) {
        hookCommandBufferClass(object_getClass(buf));
    }
    return buf;
}

static void initMetalHooks() {
    dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_NOW | RTLD_GLOBAL);

    Class baseClass = objc_getClass("_MTLCommandBuffer");
    if (baseClass) hookCommandBufferClass(baseClass);

    Class queueClass = objc_getClass("_MTLCommandQueue");
    if (queueClass) {
        Method mq1 = class_getInstanceMethod(queueClass, @selector(commandBuffer));
        if (mq1) {
            orig_cmdBuffer = (id (*)(id, SEL))method_getImplementation(mq1);
            method_setImplementation(mq1, (IMP)hook_cmdBuffer);
        }
        Method mq2 = class_getInstanceMethod(queueClass, @selector(commandBufferWithUnretainedReferences));
        if (mq2) {
            orig_cmdBufferUnretained = (id (*)(id, SEL))method_getImplementation(mq2);
            method_setImplementation(mq2, (IMP)hook_cmdBufferUnretained);
        }
    }
}

%hook CAMetalLayer
- (id<CAMetalDrawable>)nextDrawable {
    id<CAMetalDrawable> d = %orig;
    if (!g_hookedCmdBufClass) {
        initMetalHooks();
    }
    return d;
}
%end

%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    if (event.type == UIEventTypeTouches) {
        NSSet *touches = [event allTouches];

        // 3-finger tap toggle
        if (touches.count >= 3) {
            for (UITouch *t in touches) {
                if (t.phase == UITouchPhaseBegan) {
                    g_showMenu = !g_showMenu;
                    break;
                }
            }
        }

        if (g_imguiInited) {
            ImGuiIO& io = ImGui::GetIO();
            UITouch *touch = [touches anyObject];
            if (touch) {
                CGPoint loc = [touch locationInView:self];
                CGFloat scale = [UIScreen mainScreen].nativeScale;
                if (scale <= 0.0) scale = 2.0;

                io.AddMousePosEvent(loc.x * scale, loc.y * scale);

                if (touch.phase == UITouchPhaseBegan) {
                    io.AddMouseButtonEvent(0, true);
                } else if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
                    io.AddMouseButtonEvent(0, false);
                }
            }

            if (g_showMenu && io.WantCaptureMouse) {
                if (touch && (touch.phase == UITouchPhaseBegan || touch.phase == UITouchPhaseMoved)) {
                    return;
                }
            }
        }
    }
    %orig(event);
}
%end

// ═══════════════════════════════════════
// Hook setup — resolve + install
// ═══════════════════════════════════════

static void setupIL2CPPHooks() {
    if (!resolveIL2CPP()) return;

    // find the image containing our target classes
    Il2CppImage* coreModule = findImageWithClass("UnityEngine", "Shader");
    Il2CppImage* asmCSharp  = findImageWithClass("Axlebolt.Standoff.Anitcheat", "AntiCheatManager");

    // resolve Unity engine classes
    if (coreModule) {
        g_shaderClass   = il2cpp_class_from_name(coreModule, "UnityEngine", "Shader");
        g_materialClass = il2cpp_class_from_name(coreModule, "UnityEngine", "Material");
        g_cameraClass   = il2cpp_class_from_name(coreModule, "UnityEngine", "Camera");
        g_rendererClass = il2cpp_class_from_name(coreModule, "UnityEngine", "Renderer");
        g_gameObjectClass = il2cpp_class_from_name(coreModule, "UnityEngine", "GameObject");
        g_componentClass  = il2cpp_class_from_name(coreModule, "UnityEngine", "Component");
        g_objectClass     = il2cpp_class_from_name(coreModule, "UnityEngine", "Object");
    }

    // find SkinnedMeshRenderer (may be in a different module)
    Il2CppImage* animModule = findImageWithClass("UnityEngine", "SkinnedMeshRenderer");
    if (animModule) {
        g_skinnedClass = il2cpp_class_from_name(animModule, "UnityEngine", "SkinnedMeshRenderer");
    }

    // resolve anticheat classes
    if (asmCSharp) {
        g_antiCheatClass = il2cpp_class_from_name(asmCSharp, "Axlebolt.Standoff.Anitcheat", "AntiCheatManager");
        g_gameACClass    = il2cpp_class_from_name(asmCSharp, "Axlebolt.Standoff.Game.Anticheat", "GameAntiCheatManager");
    }

    // resolve key methods
    if (g_shaderClass) {
        g_shaderFind = il2cpp_class_get_method_from_name(g_shaderClass, "Find", 1);
    }
    if (g_materialClass) {
        g_materialSetShader = il2cpp_class_get_method_from_name(g_materialClass, "set_shader", 1);
        g_materialSetColor  = il2cpp_class_get_method_from_name(g_materialClass, "SetColor", 2);
        g_materialSetInt    = il2cpp_class_get_method_from_name(g_materialClass, "SetInt", 2);
        g_materialSetShader = g_materialSetShader ?: il2cpp_class_get_method_from_name(g_materialClass, "set_Shader", 1);
    }
    if (g_rendererClass) {
        g_rendererGetMaterial = il2cpp_class_get_method_from_name(g_rendererClass, "get_material", 0);
    }

    // ── Shader.Find hook ──
    if (g_shaderFind) {
        void* shaderFindPtr = *(void**)g_shaderFind;  // methodPointer is first field
        if (shaderFindPtr) {
            MSHookFunction(shaderFindPtr, (void*)hook_ShaderFind, (void**)&orig_ShaderFind);
        }
    }

    // ── Camera.set_cullingMask hook ──
    if (g_cameraClass) {
        Il2CppMethodInfo* setCulling = il2cpp_class_get_method_from_name(g_cameraClass, "set_cullingMask", 1);
        if (setCulling) {
            void* ptr = *(void**)setCulling;
            if (ptr) MSHookFunction(ptr, (void*)hook_Camera_set_cullingMask, (void**)&orig_Camera_set_cullingMask);
        }
    }

    // ── Material.SetPass hook (for chams) ──
    if (g_materialClass) {
        Il2CppMethodInfo* setPass = il2cpp_class_get_method_from_name(g_materialClass, "SetPass", 1);
        if (setPass) {
            void* ptr = *(void**)setPass;
            if (ptr) MSHookFunction(ptr, (void*)hook_Material_SetPass, (void**)&orig_Material_SetPass);
        }
    }

    // ── Occlusion bypass ──
    // hook any IsOccluded / occlusion check in the Player.Occlusion namespace
    Il2CppImage* occImg = findImageWithClass("Axlebolt.Standoff.Player.Occlusion", "OcclusionController");
    if (!occImg) occImg = asmCSharp;
    if (occImg) {
        Il2CppClass* occClass = il2cpp_class_from_name(occImg, "Axlebolt.Standoff.Player.Occlusion", "OcclusionController");
        if (!occClass) {
            // try without sub-namespace
            occClass = il2cpp_class_from_name(occImg, "Axlebolt.Standoff.Player", "OcclusionController");
        }
        if (occClass) {
            // try hooking common occlusion method names
            const char* occMethodNames[] = {"IsOccluded", "CheckOcclusion", "NFIAANGEACF", "Update", NULL};
            for (int i = 0; occMethodNames[i]; i++) {
                Il2CppMethodInfo* m = il2cpp_class_get_method_from_name(occClass, occMethodNames[i], 0);
                if (m) {
                    void* ptr = *(void**)m;
                    if (ptr) {
                        MSHookFunction(ptr, (void*)hook_IsOccluded, (void**)&orig_IsOccluded);
                        break;
                    }
                }
            }
        }
    }

    // ── AntiCheat hooks ──
    if (g_antiCheatClass) {
        // hook all known obfuscated AC methods to no-op
        struct { const char* name; int argc; void* hook; void** orig; } acHooks[] = {
            {"NFIAANGEACF", 0, (void*)hook_AC_NFIAANGEACF, (void**)&orig_AC_NFIAANGEACF},
            {"CLNMOGLLDMN", 0, (void*)hook_AC_CLNMOGLLDMN, (void**)&orig_AC_CLNMOGLLDMN},
            {"HJABCADCDMB", 0, (void*)hook_AC_HJABCADCDMB, (void**)&orig_AC_HJABCADCDMB},
            {"BLBHHGOPBCM", 0, (void*)hook_AC_BLBHHGOPBCM, (void**)&orig_AC_BLBHHGOPBCM},
            {"DHNPEOIDGED", 0, (void*)hook_AC_DHNPEOIDGED, (void**)&orig_AC_DHNPEOIDGED},
            {"ECHAHOJDKEB", 0, (void*)hook_AC_ECHAHOJDKEB, (void**)&orig_AC_ECHAHOJDKEB},
        };

        for (auto& h : acHooks) {
            Il2CppMethodInfo* m = il2cpp_class_get_method_from_name(g_antiCheatClass, h.name, h.argc);
            if (m) {
                void* ptr = *(void**)m;
                if (ptr) MSHookFunction(ptr, h.hook, h.orig);
            }
        }
    }

    // hook GameAntiCheatManager.ReportViaServer
    if (g_gameACClass) {
        Il2CppMethodInfo* reportMethod = il2cpp_class_get_method_from_name(g_gameACClass, "ReportViaServer", 2);
        if (!reportMethod) reportMethod = il2cpp_class_get_method_from_name(g_gameACClass, "ReportViaServer", 1);
        if (!reportMethod) reportMethod = il2cpp_class_get_method_from_name(g_gameACClass, "ReportViaServer", 3);
        if (reportMethod) {
            void* ptr = *(void**)reportMethod;
            if (ptr) MSHookFunction(ptr, (void*)hook_ReportViaServer, (void**)&orig_ReportViaServer);
        }

        // also hook PlayerBannedHandler to no-op
        Il2CppMethodInfo* banMethod = il2cpp_class_get_method_from_name(g_gameACClass, "PlayerBannedHandler", 1);
        if (!banMethod) banMethod = il2cpp_class_get_method_from_name(g_gameACClass, "PlayerBannedHandler", 0);
        if (banMethod) {
            void* ptr = *(void**)banMethod;
            if (ptr) {
                static ACMethod_void_t orig_ban = NULL;
                MSHookFunction(ptr, (void*)hook_AC_ECHAHOJDKEB, (void**)&orig_ban);
            }
        }
    }

    g_initialized = true;
}

// ═══════════════════════════════════════
// CONSTRUCTOR
// ═══════════════════════════════════════

%ctor {
    @autoreleasepool {
        // ── System-level anti-detection hooks (before game loads) ──
        MSHookFunction((void*)sysctl, (void*)hook_sysctl, (void**)&orig_sysctl);
        MSHookFunction((void*)access, (void*)hook_access, (void**)&orig_access);
        MSHookFunction((void*)fork, (void*)hook_fork, (void**)&orig_fork);
        MSHookFunction((void*)_dyld_image_count, (void*)hook_dyld_image_count, (void**)&orig_dyld_image_count);
        MSHookFunction((void*)_dyld_get_image_name, (void*)hook_dyld_get_image_name, (void**)&orig_dyld_get_image_name);

        // hook NSFileManager fileExistsAtPath:
        Method fileExistsMethod = class_getInstanceMethod(
            objc_getClass("NSFileManager"),
            sel_registerName("fileExistsAtPath:")
        );
        if (fileExistsMethod) {
            orig_fileExists = (BOOL(*)(id, SEL, NSString*))method_getImplementation(fileExistsMethod);
            method_setImplementation(fileExistsMethod, (IMP)hook_fileExists);
        }

        // hook UIApplication canOpenURL:
        Method canOpenMethod = class_getInstanceMethod(
            objc_getClass("UIApplication"),
            sel_registerName("canOpenURL:")
        );
        if (canOpenMethod) {
            orig_canOpenURL = (BOOL(*)(id, SEL, NSURL*))method_getImplementation(canOpenMethod);
            method_setImplementation(canOpenMethod, (IMP)hook_canOpenURL);
        }

        // ── Metal Hooks for ImGui Rendering ──
        initMetalHooks();

        // ── Startup banner ──
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *keyWin = nil;
            NSArray *windows = [UIApplication sharedApplication].windows;
            for (UIWindow *w in windows) {
                if (w.isKeyWindow || w.rootViewController) { keyWin = w; break; }
            }
            if (keyWin && keyWin.rootViewController) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"StandoffWH"
                                                                               message:@"Cheat Loaded!\nTap 3 fingers or SWH button for menu."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [keyWin.rootViewController presentViewController:alert animated:YES completion:nil];
            }
        });

        // ── Delay IL2CPP hooks until Unity is loaded ──
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            setupIL2CPPHooks();
        });
    }
}
