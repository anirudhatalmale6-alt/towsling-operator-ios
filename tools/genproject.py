#!/usr/bin/env python3
"""
Generate TowSlingOperator.xcodeproj/project.pbxproj.

WHY THIS EXISTS
---------------
The first version of this project used Xcode 16's file-system synchronised
groups (objectVersion 77, PBXFileSystemSynchronizedRootGroup). They are lovely
— files are picked up from the folder with no project edit and nothing to
merge-conflict — and they are also a hard requirement on Xcode 16. On anything
older the project will not open, let alone build, and the failure does not say
"wrong Xcode version"; it says something unhelpful about a corrupt project.

Since I cannot run Xcode here, I cannot tell that failure apart from a Swift
compile error by looking. So the format goes back to a conventional one that
Xcode 14 and later all read, and every file is listed explicitly.

Listing files by hand is what synchronised groups avoid, so this script does it
instead: run it after adding or removing a source file and commit the result.

    python3 tools/genproject.py
"""

import os
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = "TowSlingOperator"
SRC = ROOT / APP

BUNDLE_ID = "com.towsling.operator"
DEPLOYMENT_TARGET = "16.0"
MARKETING_VERSION = "0.1.0"

# Deterministic ids so re-running produces the same file and the diff stays
# readable. Xcode only needs them unique within the project.
_counter = 0
def uid() -> str:
    global _counter
    _counter += 1
    return f"7A{_counter:022X}"


def collect():
    """Every source and resource, grouped by the folder it lives in."""
    sources, resources = [], []
    for path in sorted(SRC.rglob("*")):
        if path.is_dir():
            if path.suffix == ".xcassets":
                resources.append(path)
            continue
        # Skip anything inside an asset catalog: the catalog itself is the
        # resource, and adding its contents individually makes Xcode build
        # duplicates.
        if any(p.suffix == ".xcassets" for p in path.parents):
            continue
        if path.suffix == ".swift":
            sources.append(path)
    return sources, resources


def main():
    sources, resources = collect()
    if not sources:
        raise SystemExit("no .swift files found — wrong directory?")

    files = [(p, uid(), uid()) for p in sources + resources]   # path, fileRef, buildFile

    proj_uid       = uid()
    target_uid     = uid()
    product_uid    = uid()
    main_group     = uid()
    products_group = uid()
    app_group      = uid()
    sources_phase  = uid()
    frameworks     = uid()
    resources_ph   = uid()
    proj_cfg_list  = uid()
    tgt_cfg_list   = uid()
    proj_debug, proj_release = uid(), uid()
    tgt_debug, tgt_release   = uid(), uid()

    # ── folder tree ─────────────────────────────────────────────────────
    # A group per directory under the app folder, so the navigator matches
    # what is actually on disk.
    dirs = {}
    for p, _, _ in files:
        rel = p.relative_to(SRC).parent
        dirs.setdefault(rel, uid())
    dirs.setdefault(pathlib.Path("."), app_group)
    dirs[pathlib.Path(".")] = app_group

    def children_of(rel):
        out = []
        for sub, guid in sorted(dirs.items()):
            if sub != rel and sub.parent == rel:
                out.append((guid, sub.name))
        for p, fref, _ in files:
            if p.relative_to(SRC).parent == rel:
                out.append((fref, p.name))
        return out

    L = []
    add = L.append

    add("// !$*UTF8*$!")
    add("{")
    add("\tarchiveVersion = 1;")
    add("\tclasses = {")
    add("\t};")
    add("\tobjectVersion = 56;")
    add("\tobjects = {")

    # ── PBXBuildFile ────────────────────────────────────────────────────
    add("\n/* Begin PBXBuildFile section */")
    for p, fref, bfile in files:
        add(f"\t\t{bfile} /* {p.name} in Build */ = {{isa = PBXBuildFile; fileRef = {fref} /* {p.name} */; }};")
    add("/* End PBXBuildFile section */")

    # ── PBXFileReference ────────────────────────────────────────────────
    add("\n/* Begin PBXFileReference section */")
    add(f'\t\t{product_uid} /* {APP}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
    for p, fref, _ in files:
        if p.suffix == ".swift":
            t = "sourcecode.swift"
        elif p.suffix == ".xcassets":
            t = "folder.assetcatalog"
        else:
            t = "text"
        add(f'\t\t{fref} /* {p.name} */ = {{isa = PBXFileReference; lastKnownFileType = {t}; path = "{p.name}"; sourceTree = "<group>"; }};')
    add("/* End PBXFileReference section */")

    # ── PBXFrameworksBuildPhase ─────────────────────────────────────────
    add("\n/* Begin PBXFrameworksBuildPhase section */")
    add(f"\t\t{frameworks} /* Frameworks */ = {{")
    add("\t\t\tisa = PBXFrameworksBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (\n\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXFrameworksBuildPhase section */")

    # ── PBXGroup ────────────────────────────────────────────────────────
    add("\n/* Begin PBXGroup section */")
    add(f"\t\t{main_group} = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{app_group} /* {APP} */,")
    add(f"\t\t\t\t{products_group} /* Products */,")
    add("\t\t\t);")
    add('\t\t\tsourceTree = "<group>";')
    add("\t\t};")

    add(f"\t\t{products_group} /* Products */ = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{product_uid} /* {APP}.app */,")
    add("\t\t\t);")
    add("\t\t\tname = Products;")
    add('\t\t\tsourceTree = "<group>";')
    add("\t\t};")

    for rel, guid in sorted(dirs.items()):
        name = APP if rel == pathlib.Path(".") else rel.name
        add(f"\t\t{guid} /* {name} */ = {{")
        add("\t\t\tisa = PBXGroup;")
        add("\t\t\tchildren = (")
        for cuid, cname in children_of(rel):
            add(f"\t\t\t\t{cuid} /* {cname} */,")
        add("\t\t\t);")
        add(f'\t\t\tpath = "{name}";')
        add('\t\t\tsourceTree = "<group>";')
        add("\t\t};")
    add("/* End PBXGroup section */")

    # ── PBXNativeTarget ─────────────────────────────────────────────────
    add("\n/* Begin PBXNativeTarget section */")
    add(f"\t\t{target_uid} /* {APP} */ = {{")
    add("\t\t\tisa = PBXNativeTarget;")
    add(f'\t\t\tbuildConfigurationList = {tgt_cfg_list} /* Build configuration list for PBXNativeTarget "{APP}" */;')
    add("\t\t\tbuildPhases = (")
    add(f"\t\t\t\t{sources_phase} /* Sources */,")
    add(f"\t\t\t\t{frameworks} /* Frameworks */,")
    add(f"\t\t\t\t{resources_ph} /* Resources */,")
    add("\t\t\t);")
    add("\t\t\tbuildRules = (\n\t\t\t);")
    add("\t\t\tdependencies = (\n\t\t\t);")
    add(f"\t\t\tname = {APP};")
    add(f"\t\t\tproductName = {APP};")
    add(f"\t\t\tproductReference = {product_uid} /* {APP}.app */;")
    add('\t\t\tproductType = "com.apple.product-type.application";')
    add("\t\t};")
    add("/* End PBXNativeTarget section */")

    # ── PBXProject ──────────────────────────────────────────────────────
    add("\n/* Begin PBXProject section */")
    add(f"\t\t{proj_uid} /* Project object */ = {{")
    add("\t\t\tisa = PBXProject;")
    add("\t\t\tattributes = {")
    add("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    add("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    add("\t\t\t\tLastUpgradeCheck = 1500;")
    add("\t\t\t\tTargetAttributes = {")
    add(f"\t\t\t\t\t{target_uid} = {{")
    add("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    add("\t\t\t\t\t};")
    add("\t\t\t\t};")
    add("\t\t\t};")
    add(f'\t\t\tbuildConfigurationList = {proj_cfg_list} /* Build configuration list for PBXProject "{APP}" */;')
    add("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    add("\t\t\tdevelopmentRegion = en;")
    add("\t\t\thasScannedForEncodings = 0;")
    add("\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);")
    add(f"\t\t\tmainGroup = {main_group};")
    add(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
    add('\t\t\tprojectDirPath = "";')
    add('\t\t\tprojectRoot = "";')
    add("\t\t\ttargets = (")
    add(f"\t\t\t\t{target_uid} /* {APP} */,")
    add("\t\t\t);")
    add("\t\t};")
    add("/* End PBXProject section */")

    # ── Resources / Sources phases ──────────────────────────────────────
    add("\n/* Begin PBXResourcesBuildPhase section */")
    add(f"\t\t{resources_ph} /* Resources */ = {{")
    add("\t\t\tisa = PBXResourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for p, _, bfile in files:
        if p.suffix == ".xcassets":
            add(f"\t\t\t\t{bfile} /* {p.name} in Resources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXResourcesBuildPhase section */")

    add("\n/* Begin PBXSourcesBuildPhase section */")
    add(f"\t\t{sources_phase} /* Sources */ = {{")
    add("\t\t\tisa = PBXSourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for p, _, bfile in files:
        if p.suffix == ".swift":
            add(f"\t\t\t\t{bfile} /* {p.name} in Sources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXSourcesBuildPhase section */")

    # ── Build settings ──────────────────────────────────────────────────
    common = f"""				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				IPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;"""

    target_common = f"""				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleDisplayName = TowSling;
				INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "Your location is shared with the customer only while you are working their job, so they can watch your truck arrive.";
				INFOPLIST_KEY_NSCameraUsageDescription = "Photographing a vehicle before and after a tow is what protects you against a damage claim.";
				INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "Only used to pick a job photo when the camera is not available, such as on a simulator.";
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleLightContent;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;
				INFOPLIST_KEY_UIUserInterfaceStyle = Dark;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = {MARKETING_VERSION};
				PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				TARGETED_DEVICE_FAMILY = "1,2";"""

    add("\n/* Begin XCBuildConfiguration section */")
    for guid, name, extra in [
        (proj_debug, "Debug",
         '				DEBUG_INFORMATION_FORMAT = dwarf;\n'
         '				ENABLE_TESTABILITY = YES;\n'
         '				GCC_DYNAMIC_NO_PIC = NO;\n'
         '				GCC_OPTIMIZATION_LEVEL = 0;\n'
         '				GCC_PREPROCESSOR_DEFINITIONS = (\n					"DEBUG=1",\n					"$(inherited)",\n				);\n'
         '				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;\n'
         '				ONLY_ACTIVE_ARCH = YES;\n'
         '				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n'
         '				SWIFT_OPTIMIZATION_LEVEL = "-Onone";'),
        (proj_release, "Release",
         '				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";\n'
         '				ENABLE_NS_ASSERTIONS = NO;\n'
         '				MTL_ENABLE_DEBUG_INFO = NO;\n'
         '				SWIFT_COMPILATION_MODE = wholemodule;\n'
         '				VALIDATE_PRODUCT = YES;'),
    ]:
        add(f"\t\t{guid} /* {name} */ = {{")
        add("\t\t\tisa = XCBuildConfiguration;")
        add("\t\t\tbuildSettings = {")
        add(common)
        add(extra)
        add("\t\t\t};")
        add(f"\t\t\tname = {name};")
        add("\t\t};")

    for guid, name in [(tgt_debug, "Debug"), (tgt_release, "Release")]:
        add(f"\t\t{guid} /* {name} */ = {{")
        add("\t\t\tisa = XCBuildConfiguration;")
        add("\t\t\tbuildSettings = {")
        add(target_common)
        add("\t\t\t};")
        add(f"\t\t\tname = {name};")
        add("\t\t};")
    add("/* End XCBuildConfiguration section */")

    add("\n/* Begin XCConfigurationList section */")
    for guid, label, d, r in [
        (proj_cfg_list, f'Build configuration list for PBXProject "{APP}"', proj_debug, proj_release),
        (tgt_cfg_list,  f'Build configuration list for PBXNativeTarget "{APP}"', tgt_debug, tgt_release),
    ]:
        add(f"\t\t{guid} /* {label} */ = {{")
        add("\t\t\tisa = XCConfigurationList;")
        add("\t\t\tbuildConfigurations = (")
        add(f"\t\t\t\t{d} /* Debug */,")
        add(f"\t\t\t\t{r} /* Release */,")
        add("\t\t\t);")
        add("\t\t\tdefaultConfigurationIsVisible = 0;")
        add("\t\t\tdefaultConfigurationName = Release;")
        add("\t\t};")
    add("/* End XCConfigurationList section */")

    add("\t};")
    add(f"\trootObject = {proj_uid} /* Project object */;")
    add("}")

    out = ROOT / f"{APP}.xcodeproj" / "project.pbxproj"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(L) + "\n", encoding="utf-8")

    write_scheme(target_uid, product_uid)

    print(f"wrote {out.relative_to(ROOT)}")
    print(f"  {len([f for f in sources])} swift files, {len(resources)} resource(s)")
    for p in sources:
        print("   ", p.relative_to(SRC))



def write_scheme(target_uid: str, product_uid: str) -> None:
    """
    A SHARED scheme, committed to the repo.

    Xcode invents one the first time somebody opens the project, but it puts it
    in xcuserdata — per-user, gitignored, and invisible to `xcodebuild`. So a
    fresh clone has no scheme to name, and a command line build fails with
    "scheme not found" before it has compiled a line. Sharing it means the
    project builds the same way for Xcode and for the terminal, which matters
    when the person who wrote it cannot run either.
    """
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES"
                           buildForProfiling = "YES" buildForArchiving = "YES"
                           buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_uid}"
               BuildableName = "{APP}.app"
               BlueprintName = "{APP}"
               ReferencedContainer = "container:{APP}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES" debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_uid}"
            BuildableName = "{APP}.app"
            BlueprintName = "{APP}"
            ReferencedContainer = "container:{APP}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_uid}"
            BuildableName = "{APP}.app"
            BlueprintName = "{APP}"
            ReferencedContainer = "container:{APP}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    path = ROOT / f"{APP}.xcodeproj" / "xcshareddata" / "xcschemes" / f"{APP}.xcscheme"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(scheme, encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
