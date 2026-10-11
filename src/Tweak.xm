// StandoffWH — Wallhack tweak for Standoff 2 (Unity IL2CPP, iOS arm64)
// Runtime IL2CPP resolution + shader-based WH + anticheat bypass

#import <substrate.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

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
        // force ZTest Always on this material
        setMaterialInt(self, "_ZTest", 8); // 8 = Always in Unity
        setMaterialInt(self, "_ZWrite", 0);

        // color tint — green for friendly visibility
        UnityColor chamColor = {0.0f, 1.0f, 0.2f, 0.7f};
        setMaterialColor(self, "_Color", chamColor);
    }
    return ret;
}

// ═══════════════════════════════════════
// Toggle Menu (simple floating button)
// ═══════════════════════════════════════

@interface WHMenuView : UIView
@property (nonatomic, strong) UIButton* whButton;
@property (nonatomic, strong) UIButton* chamButton;
@property (nonatomic, strong) UILabel* statusLabel;
@end

@implementation WHMenuView

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 160, 130)];
    if (self) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        self.layer.cornerRadius = 12;
        self.layer.borderColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.4 alpha:1.0].CGColor;
        self.layer.borderWidth = 1.5;
        self.clipsToBounds = YES;

        UILabel* title = [[UILabel alloc] initWithFrame:CGRectMake(0, 6, 160, 22)];
        title.text = @"StandoffWH";
        title.textColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.4 alpha:1.0];
        title.font = [UIFont boldSystemFontOfSize:14];
        title.textAlignment = NSTextAlignmentCenter;
        [self addSubview:title];

        _whButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _whButton.frame = CGRectMake(10, 34, 140, 34);
        [_whButton setTitle:@"Wallhack: ON" forState:UIControlStateNormal];
        [_whButton setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        _whButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _whButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
        _whButton.layer.cornerRadius = 6;
        [_whButton addTarget:self action:@selector(toggleWH) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_whButton];

        _chamButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _chamButton.frame = CGRectMake(10, 74, 140, 34);
        [_chamButton setTitle:@"Chams: ON" forState:UIControlStateNormal];
        [_chamButton setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        _chamButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _chamButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
        _chamButton.layer.cornerRadius = 6;
        [_chamButton addTarget:self action:@selector(toggleCham) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_chamButton];

        // draggable
        UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)toggleWH {
    g_wallhackEnabled = !g_wallhackEnabled;
    [_whButton setTitle:g_wallhackEnabled ? @"Wallhack: ON" : @"Wallhack: OFF" forState:UIControlStateNormal];
    [_whButton setTitleColor:g_wallhackEnabled ? [UIColor greenColor] : [UIColor redColor] forState:UIControlStateNormal];
}

- (void)toggleCham {
    g_chamEnabled = !g_chamEnabled;
    [_chamButton setTitle:g_chamEnabled ? @"Chams: ON" : @"Chams: OFF" forState:UIControlStateNormal];
    [_chamButton setTitleColor:g_chamEnabled ? [UIColor greenColor] : [UIColor redColor] forState:UIControlStateNormal];
}

- (void)handlePan:(UIPanGestureRecognizer*)pan {
    CGPoint translation = [pan translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:self.superview];
}

@end

static WHMenuView* g_menuView = nil;

static void showMenu() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_menuView) return;

        UIWindow* keyWindow = nil;
        for (UIWindowScene* scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow* window in scene.windows) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }
            }
        }
        if (!keyWindow) {
            keyWindow = [UIApplication sharedApplication].windows.firstObject;
        }

        g_menuView = [[WHMenuView alloc] init];
        [keyWindow addSubview:g_menuView];
    });
}

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

        // ── Delay IL2CPP hooks until Unity is loaded ──
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            setupIL2CPPHooks();
            showMenu();
        });
    }
}
