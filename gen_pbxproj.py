#!/usr/bin/env python3
"""Generate MileagePocket.xcodeproj/project.pbxproj.

Recursively scans each target's source directories, mirroring the directory tree as
nested PBXGroups. `Shared/` is compiled into every target (app, widget extension, and —
once added — the watch app/complications) via file-reference reuse: one PBXFileReference
per physical file, one PBXBuildFile per (file, target) pair that compiles it. Deterministic
UUIDs (hash of a role key) so re-runs are stable and diff-friendly.
"""
import os
import hashlib

ROOT = os.path.dirname(os.path.abspath(__file__))
PROJ = "MileagePocket"
BUNDLE_ID_VAR = "$(BUNDLE_IDENTIFIER)"
DEVELOPMENT_TEAM = "2E6D4Q69QB"
APP_GROUP_ID = "group.company.lno.mileage"

APP_ONLY_DIRS = ["App", "Core", "Models", "Services", "Features"]
SHARED_DIR = "Shared"
TEST_SOURCE_DIR = "Tests"
UITEST_SOURCE_DIR = "UITests"
RESOURCES_DIR = "Resources"

# No third-party dependencies: Apple frameworks only, per the spec.
SPM_PACKAGES = []

# One extension: widget + Live Activity live in the same WidgetBundle, which is how
# WidgetKit expects them (a Live Activity is a widget configuration, not its own target).
EXTENSION_TARGETS = [
    {
        "key": "widget",
        "name": "MileageWidgetsExtension",
        "src_dirs": ["MileageWidgets", SHARED_DIR],
        "info_plist": "MileageWidgets/Info.plist",
        "entitlements": "MileageWidgets/MileageWidgets.entitlements",
        "bundle_id_suffix": ".widgets",
        "product_type": "com.apple.product-type.app-extension",
        "product_ext": "appex",
        "sdkroot": "iphoneos",
        "deployment_target": ("IPHONEOS_DEPLOYMENT_TARGET", "18.0"),
        "dst_subfolder_spec": 13,
        "dst_path": "",
        "embed_phase_name": "Embed Foundation Extensions",
        "host": "app",
        "device_family": "1",
        "own_assets": None,
        "extra_settings": [],
    },
]

# host key -> list of ext dicts embedded into it (built after EXTENSION_TARGETS is final).
EMBEDS_BY_HOST = {}
for _ext in EXTENSION_TARGETS:
    EMBEDS_BY_HOST.setdefault(_ext["host"], []).append(_ext)


def uid(key):
    return hashlib.md5(key.encode()).hexdigest()[:24].upper()


def find_swift_files(top_dir):
    """Returns sorted relpaths (relative to ROOT, '/'-separated) of every .swift file
    under top_dir, recursively."""
    results = []
    base = os.path.join(ROOT, top_dir)
    if not os.path.isdir(base):
        return results
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames.sort()
        rel_dir = os.path.relpath(dirpath, ROOT)
        for fn in sorted(filenames):
            if fn.endswith(".swift"):
                results.append(os.path.join(rel_dir, fn).replace(os.sep, "/"))
    return results


app_only_files = []
for d in APP_ONLY_DIRS:
    app_only_files += find_swift_files(d)
shared_files = find_swift_files(SHARED_DIR)
app_swift_files = app_only_files + shared_files

test_swift_files = find_swift_files(TEST_SOURCE_DIR)
uitest_swift_files = find_swift_files(UITEST_SOURCE_DIR)

for ext in EXTENSION_TARGETS:
    files = []
    for d in ext["src_dirs"]:
        files += shared_files if d == SHARED_DIR else find_swift_files(d)
    ext["swift_files"] = files

assets_path = f"{RESOURCES_DIR}/Assets.xcassets"
xcstrings_path = f"{RESOURCES_DIR}/Localizable.xcstrings"
info_plist_path = "App/Info.plist"
entitlements_path = "App/MileagePocket.entitlements"
xcconfig_files = ["Base.xcconfig", "Debug.xcconfig", "Release.xcconfig"]

# ---- UUID registries -----------------------------------------------------
_group_uids = {}
_fileref_uids = {}


def group_uid(path):
    key = "group:" + path
    if key not in _group_uids:
        _group_uids[key] = uid(key)
    return _group_uids[key]


def fileref_uid(path):
    key = "fileref:" + path
    if key not in _fileref_uids:
        _fileref_uids[key] = uid(key)
    return _fileref_uids[key]


def build_tree(file_list):
    """relpath list -> nested {"files": [names], "dirs": {name: subtree}}."""
    tree = {"files": [], "dirs": {}}
    for relpath in file_list:
        parts = relpath.split("/")
        node = tree
        for part in parts[:-1]:
            node = node["dirs"].setdefault(part, {"files": [], "dirs": {}})
        node["files"].append(parts[-1])
    return tree


prod_ref = uid("product.app")
test_prod_ref = uid("product.tests")
uitest_prod_ref = uid("product.uitests")
main_group = uid("group.main")
products_group = uid("group.Products")
config_group = uid("group.Config")
resources_group = uid("group.Resources")
app_target = uid("target.app")
test_target = uid("target.tests")
uitest_target = uid("target.uitests")
project_uid = uid("project")
sources_phase = uid("phase.sources")
resources_phase = uid("phase.resources")
frameworks_phase = uid("phase.frameworks")
test_sources_phase = uid("phase.test.sources")
test_frameworks_phase = uid("phase.test.frameworks")
uitest_sources_phase = uid("phase.uitest.sources")
uitest_frameworks_phase = uid("phase.uitest.frameworks")
proj_cfg_list = uid("cfglist.project")
app_cfg_list = uid("cfglist.app")
test_cfg_list = uid("cfglist.tests")
uitest_cfg_list = uid("cfglist.uitests")
test_container_proxy = uid("containerproxy.tests")
uitest_container_proxy = uid("containerproxy.uitests")
test_target_dependency = uid("targetdep.tests")
uitest_target_dependency = uid("targetdep.uitests")

assets_ref = fileref_uid(assets_path)
xcstrings_ref = fileref_uid(xcstrings_path)
info_plist_ref = fileref_uid(info_plist_path)
entitlements_ref = fileref_uid(entitlements_path)
xcconfig_refs = {f: fileref_uid("Config/" + f) for f in xcconfig_files}

app_build_files = {f: uid("buildfile.app.sources." + f) for f in app_swift_files}
test_build_files = {f: uid("buildfile.tests.sources." + f) for f in test_swift_files}
uitest_build_files = {f: uid("buildfile.uitests.sources." + f) for f in uitest_swift_files}
rules_folder_path = f"{RESOURCES_DIR}/MileageRules"
privacy_path = f"{RESOURCES_DIR}/PrivacyInfo.xcprivacy"
storekit_path = "Config/MileagePocket.storekit"
rules_ref = fileref_uid(rules_folder_path)
privacy_ref = fileref_uid(privacy_path)
storekit_ref = fileref_uid(storekit_path)
rules_build_file = uid("buildfile.rules")
privacy_build_file = uid("buildfile.privacy")
assets_build_file = uid("buildfile.assets")
xcstrings_build_file = uid("buildfile.xcstrings")

pkg_refs = {}
product_deps = {}
product_build_files = {}
for name, url, version, products in SPM_PACKAGES:
    pkg_refs[name] = uid("pkgref." + name)
    for prod in products:
        product_deps[prod] = uid("proddep." + prod)
        product_build_files[prod] = uid("buildfile.product." + prod)

# ---- Extension target UUIDs / derived data --------------------------------------
for ext in EXTENSION_TARGETS:
    key = ext["key"]
    ext["target_uid"] = uid("target." + key)
    ext["prod_ref"] = uid("product." + key)
    ext["sources_phase"] = uid("phase." + key + ".sources")
    ext["resources_phase"] = uid("phase." + key + ".resources")
    ext["frameworks_phase"] = uid("phase." + key + ".frameworks")
    ext["cfg_list"] = uid("cfglist." + key)
    ext["container_proxy"] = uid("containerproxy." + key)
    ext["target_dependency"] = uid("targetdep." + key)
    ext["embed_buildfile"] = uid("buildfile.embed." + key)
    ext["xcstrings_build_file"] = uid("buildfile." + key + ".xcstrings")
    if ext["own_assets"]:
        ext["assets_ref"] = fileref_uid(ext["own_assets"])
        ext["assets_build_file"] = uid("buildfile." + key + ".assets")
    ext["info_plist_ref"] = fileref_uid(ext["info_plist"])
    ext["entitlements_ref"] = fileref_uid(ext["entitlements"])
    ext["build_files"] = {f: uid(f"buildfile.{key}.sources." + f) for f in ext["swift_files"]}
    ext["embed_phase_uid"] = uid("phase.embed." + key)

lines = []


def L(s=""):
    lines.append(s)


# ---- Recursive group emission ---------------------------------------------
_emitted_groups = set()


def emit_group(node, path_prefix, dir_name):
    """Emits a PBXGroup for this node (and recursively for its subdirs) and returns its
    uid. Idempotent — a directory shared by multiple targets (e.g. Shared/) is only
    emitted once, the second call just returns the cached uid."""
    my_path = f"{path_prefix}/{dir_name}" if path_prefix else dir_name
    this_uid = group_uid(my_path)
    if my_path in _emitted_groups:
        return this_uid
    _emitted_groups.add(my_path)

    child_refs = []
    for sub_name in sorted(node["dirs"].keys()):
        sub_uid = emit_group(node["dirs"][sub_name], my_path, sub_name)
        child_refs.append((sub_uid, sub_name))
    for fname in sorted(node["files"]):
        relpath = f"{my_path}/{fname}"
        child_refs.append((fileref_uid(relpath), fname))

    L('\t\t%s /* %s */ = {' % (this_uid, dir_name))
    L('\t\t\tisa = PBXGroup;')
    L('\t\t\tchildren = (')
    for child_uid, comment in child_refs:
        L('\t\t\t\t%s /* %s */,' % (child_uid, comment))
    L('\t\t\t);')
    L('\t\t\tpath = %s;' % dir_name)
    L('\t\t\tsourceTree = "<group>";')
    L('\t\t};')
    return this_uid


def emit_top_level_group(dir_name, file_list):
    tree = build_tree(file_list)
    node = tree.get("dirs", {}).get(dir_name, {"files": [f.split("/", 1)[1] for f in file_list if "/" in f], "dirs": {}})
    return emit_group(node, "", dir_name)


# ================================================================================
L("// !$*UTF8*$!")
L("{")
L("\tarchiveVersion = 1;")
L("\tclasses = {")
L("\t};")
L("\tobjectVersion = 56;")
L("\tobjects = {")

# ---- PBXBuildFile ----------------------------------------------------------
L("\n/* Begin PBXBuildFile section */")
for f in app_swift_files:
    L('\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };' % (app_build_files[f], os.path.basename(f), fileref_uid(f), os.path.basename(f)))
for f in test_swift_files:
    L('\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };' % (test_build_files[f], os.path.basename(f), fileref_uid(f), os.path.basename(f)))
for f in uitest_swift_files:
    L('\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };' % (uitest_build_files[f], os.path.basename(f), fileref_uid(f), os.path.basename(f)))
for ext in EXTENSION_TARGETS:
    for f in ext["swift_files"]:
        L('\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };' % (ext["build_files"][f], os.path.basename(f), fileref_uid(f), os.path.basename(f)))
L('\t\t%s /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = %s /* Assets.xcassets */; };' % (assets_build_file, assets_ref))
L('\t\t%s /* MileageRules in Resources */ = {isa = PBXBuildFile; fileRef = %s /* MileageRules */; };' % (rules_build_file, rules_ref))
L('\t\t%s /* PrivacyInfo.xcprivacy in Resources */ = {isa = PBXBuildFile; fileRef = %s /* PrivacyInfo.xcprivacy */; };' % (privacy_build_file, privacy_ref))
L('\t\t%s /* Localizable.xcstrings in Resources */ = {isa = PBXBuildFile; fileRef = %s /* Localizable.xcstrings */; };' % (xcstrings_build_file, xcstrings_ref))
for ext in EXTENSION_TARGETS:
    L('\t\t%s /* Localizable.xcstrings in Resources */ = {isa = PBXBuildFile; fileRef = %s /* Localizable.xcstrings */; };' % (ext["xcstrings_build_file"], xcstrings_ref))
    if ext["own_assets"]:
        L('\t\t%s /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = %s /* Assets.xcassets */; };' % (ext["assets_build_file"], ext["assets_ref"]))
for prod, bf_uid in product_build_files.items():
    L('\t\t%s /* %s in Frameworks */ = {isa = PBXBuildFile; productRef = %s /* %s */; };' % (bf_uid, prod, product_deps[prod], prod))
for ext in EXTENSION_TARGETS:
    L('\t\t%s /* %s.%s in %s */ = {isa = PBXBuildFile; fileRef = %s /* %s.%s */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };' % (
        ext["embed_buildfile"], ext["name"], ext["product_ext"], ext["embed_phase_name"], ext["prod_ref"], ext["name"], ext["product_ext"]))
L("/* End PBXBuildFile section */")

# ---- PBXFileReference -------------------------------------------------------
L("\n/* Begin PBXFileReference section */")
L('\t\t%s /* %s.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "%s.app"; sourceTree = BUILT_PRODUCTS_DIR; };' % (prod_ref, PROJ, PROJ))
L('\t\t%s /* %sTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = "%sTests.xctest"; sourceTree = BUILT_PRODUCTS_DIR; };' % (test_prod_ref, PROJ, PROJ))
L('\t\t%s /* %sUITests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = "%sUITests.xctest"; sourceTree = BUILT_PRODUCTS_DIR; };' % (uitest_prod_ref, PROJ, PROJ))
for ext in EXTENSION_TARGETS:
    file_type = "wrapper.app-extension" if ext["product_type"] == "com.apple.product-type.app-extension" else "wrapper.application"
    L('\t\t%s /* %s.%s */ = {isa = PBXFileReference; explicitFileType = "%s"; includeInIndex = 0; path = "%s.%s"; sourceTree = BUILT_PRODUCTS_DIR; };' % (
        ext["prod_ref"], ext["name"], ext["product_ext"], file_type, ext["name"], ext["product_ext"]))
all_swift_files = app_swift_files + test_swift_files + uitest_swift_files
for ext in EXTENSION_TARGETS:
    all_swift_files += ext["swift_files"]
for f in sorted(set(all_swift_files)):
    L('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "%s"; sourceTree = "<group>"; };' % (fileref_uid(f), os.path.basename(f), os.path.basename(f)))
L('\t\t%s /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };' % assets_ref)
# Blue folder reference: the whole MileageRules/ tree is copied into the bundle as-is,
# so adding a country's JSON needs no pbxproj change beyond re-running this script.
L('\t\t%s /* MileageRules */ = {isa = PBXFileReference; lastKnownFileType = folder; path = MileageRules; sourceTree = "<group>"; };' % rules_ref)
L('\t\t%s /* PrivacyInfo.xcprivacy */ = {isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; };' % privacy_ref)
L('\t\t%s /* MileagePocket.storekit */ = {isa = PBXFileReference; lastKnownFileType = text; path = MileagePocket.storekit; sourceTree = "<group>"; };' % storekit_ref)
L('\t\t%s /* Localizable.xcstrings */ = {isa = PBXFileReference; lastKnownFileType = text.json.xcstrings; path = Localizable.xcstrings; sourceTree = "<group>"; };' % xcstrings_ref)
L('\t\t%s /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };' % info_plist_ref)
L('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = %s; sourceTree = "<group>"; };' % (entitlements_ref, os.path.basename(entitlements_path), os.path.basename(entitlements_path)))
for f in xcconfig_files:
    L('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = %s; sourceTree = "<group>"; };' % (xcconfig_refs[f], f, f))
for ext in EXTENSION_TARGETS:
    L('\t\t%s /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };' % ext["info_plist_ref"])
    ent_name = os.path.basename(ext["entitlements"])
    L('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = %s; sourceTree = "<group>"; };' % (ext["entitlements_ref"], ent_name, ent_name))
    if ext["own_assets"]:
        L('\t\t%s /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };' % ext["assets_ref"])
L("/* End PBXFileReference section */")

# ---- PBXFrameworksBuildPhase ------------------------------------------------
L("\n/* Begin PBXFrameworksBuildPhase section */")
for phase_uid in [frameworks_phase, test_frameworks_phase, uitest_frameworks_phase]:
    L('\t\t%s /* Frameworks */ = {' % phase_uid)
    L('\t\t\tisa = PBXFrameworksBuildPhase;')
    L('\t\t\tbuildActionMask = 2147483647;')
    L('\t\t\tfiles = (')
    if phase_uid == frameworks_phase:
        for prod, bf_uid in product_build_files.items():
            L('\t\t\t\t%s /* %s in Frameworks */,' % (bf_uid, prod))
    L('\t\t\t);')
    L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
    L('\t\t};')
for ext in EXTENSION_TARGETS:
    L('\t\t%s /* Frameworks */ = {' % ext["frameworks_phase"])
    L('\t\t\tisa = PBXFrameworksBuildPhase;')
    L('\t\t\tbuildActionMask = 2147483647;')
    L('\t\t\tfiles = (')
    L('\t\t\t);')
    L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
    L('\t\t};')
L("/* End PBXFrameworksBuildPhase section */")

# ---- PBXCopyFilesBuildPhase (embedding extensions) --------------------------
L("\n/* Begin PBXCopyFilesBuildPhase section */")
for ext in EXTENSION_TARGETS:
    L('\t\t%s /* %s */ = {' % (ext["embed_phase_uid"], ext["embed_phase_name"]))
    L('\t\t\tisa = PBXCopyFilesBuildPhase;')
    L('\t\t\tbuildActionMask = 2147483647;')
    L('\t\t\tdstPath = "%s";' % ext["dst_path"])
    L('\t\t\tdstSubfolderSpec = %d;' % ext["dst_subfolder_spec"])
    L('\t\t\tfiles = (')
    L('\t\t\t\t%s /* %s.%s in %s */,' % (ext["embed_buildfile"], ext["name"], ext["product_ext"], ext["embed_phase_name"]))
    L('\t\t\t);')
    L('\t\t\tname = "%s";' % ext["embed_phase_name"])
    L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
    L('\t\t};')
L("/* End PBXCopyFilesBuildPhase section */")

# ---- PBXGroup ---------------------------------------------------------------
L("\n/* Begin PBXGroup section */")
top_level_group_uids = {}
for dir_name in APP_ONLY_DIRS:
    top_level_group_uids[dir_name] = emit_top_level_group(dir_name, app_only_files)
shared_group_uid = emit_top_level_group(SHARED_DIR, shared_files)

test_group_uid = emit_top_level_group(TEST_SOURCE_DIR, test_swift_files)
uitest_group_uid = emit_top_level_group(UITEST_SOURCE_DIR, uitest_swift_files)

ext_own_dir_group_uids = {}
for ext in EXTENSION_TARGETS:
    own_dir = ext["src_dirs"][0]  # first entry is always the target's own folder, e.g. PilloWidgets
    # Info.plist/entitlements are folded in as plain (non-.swift) children of the same
    # group tree, not a separate sibling group — a group only reachable from mainGroup
    # resolves its members' paths correctly; anything else silently drops the directory
    # prefix (learned the hard way: source files in an orphaned group build-failed with
    # "cannot be found" at SRCROOT instead of SRCROOT/PilloWidgets).
    own_files = [f for f in ext["swift_files"] if f.startswith(own_dir + "/")] + [ext["info_plist"], ext["entitlements"]]
    if ext["own_assets"]:
        own_files.append(ext["own_assets"])
    ext_own_dir_group_uids[ext["key"]] = emit_top_level_group(own_dir, own_files)

L('\t\t%s /* Resources */ = {' % resources_group)
L('\t\t\tisa = PBXGroup;')
L('\t\t\tchildren = (')
L('\t\t\t\t%s /* Assets.xcassets */,' % assets_ref)
L('\t\t\t\t%s /* Localizable.xcstrings */,' % xcstrings_ref)
L('\t\t\t\t%s /* MileageRules */,' % rules_ref)
L('\t\t\t\t%s /* PrivacyInfo.xcprivacy */,' % privacy_ref)
L('\t\t\t);')
L('\t\t\tpath = %s;' % RESOURCES_DIR)
L('\t\t\tsourceTree = "<group>";')
L('\t\t};')

L('\t\t%s /* Config */ = {' % config_group)
L('\t\t\tisa = PBXGroup;')
L('\t\t\tchildren = (')
for f in xcconfig_files:
    L('\t\t\t\t%s /* %s */,' % (xcconfig_refs[f], f))
L('\t\t\t\t%s /* MileagePocket.storekit */,' % storekit_ref)
L('\t\t\t);')
L('\t\t\tpath = Config;')
L('\t\t\tsourceTree = "<group>";')
L('\t\t};')

L('\t\t%s /* Products */ = {' % products_group)
L('\t\t\tisa = PBXGroup;')
L('\t\t\tchildren = (')
L('\t\t\t\t%s /* %s.app */,' % (prod_ref, PROJ))
L('\t\t\t\t%s /* %sTests.xctest */,' % (test_prod_ref, PROJ))
L('\t\t\t\t%s /* %sUITests.xctest */,' % (uitest_prod_ref, PROJ))
for ext in EXTENSION_TARGETS:
    L('\t\t\t\t%s /* %s.%s */,' % (ext["prod_ref"], ext["name"], ext["product_ext"]))
L('\t\t\t);')
L('\t\t\tname = Products;')
L('\t\t\tsourceTree = "<group>";')
L('\t\t};')

L('\t\t%s = {' % main_group)
L('\t\t\tisa = PBXGroup;')
L('\t\t\tchildren = (')
for dir_name in APP_ONLY_DIRS:
    L('\t\t\t\t%s /* %s */,' % (top_level_group_uids[dir_name], dir_name))
L('\t\t\t\t%s /* %s */,' % (shared_group_uid, SHARED_DIR))
L('\t\t\t\t%s /* Resources */,' % resources_group)
L('\t\t\t\t%s /* Config */,' % config_group)
L('\t\t\t\t%s /* Tests */,' % test_group_uid)
L('\t\t\t\t%s /* UITests */,' % uitest_group_uid)
for ext in EXTENSION_TARGETS:
    own_dir = ext["src_dirs"][0]
    L('\t\t\t\t%s /* %s */,' % (ext_own_dir_group_uids[ext["key"]], own_dir))
L('\t\t\t\t%s /* Products */,' % products_group)
L('\t\t\t);')
L('\t\t\tsourceTree = "<group>";')
L('\t\t};')
L("/* End PBXGroup section */")

# ---- PBXNativeTarget ---------------------------------------------------------
L("\n/* Begin PBXNativeTarget section */")
L('\t\t%s /* %s */ = {' % (app_target, PROJ))
L('\t\t\tisa = PBXNativeTarget;')
L('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "%s" */;' % (app_cfg_list, PROJ))
L('\t\t\tbuildPhases = (')
L('\t\t\t\t%s /* Sources */,' % sources_phase)
L('\t\t\t\t%s /* Frameworks */,' % frameworks_phase)
L('\t\t\t\t%s /* Resources */,' % resources_phase)
for ext in EMBEDS_BY_HOST.get("app", []):
    L('\t\t\t\t%s /* %s */,' % (ext["embed_phase_uid"], ext["embed_phase_name"]))
L('\t\t\t);')
L('\t\t\tbuildRules = (')
L('\t\t\t);')
L('\t\t\tdependencies = (')
for ext in EMBEDS_BY_HOST.get("app", []):
    L('\t\t\t\t%s /* PBXTargetDependency */,' % ext["target_dependency"])
L('\t\t\t);')
L('\t\t\tname = %s;' % PROJ)
L('\t\t\tpackageProductDependencies = (')
for prod, dep_uid in product_deps.items():
    L('\t\t\t\t%s /* %s */,' % (dep_uid, prod))
L('\t\t\t);')
L('\t\t\tproductName = %s;' % PROJ)
L('\t\t\tproductReference = %s /* %s.app */;' % (prod_ref, PROJ))
L('\t\t\tproductType = "com.apple.product-type.application";')
L('\t\t};')

L('\t\t%s /* %sTests */ = {' % (test_target, PROJ))
L('\t\t\tisa = PBXNativeTarget;')
L('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "%sTests" */;' % (test_cfg_list, PROJ))
L('\t\t\tbuildPhases = (')
L('\t\t\t\t%s /* Sources */,' % test_sources_phase)
L('\t\t\t\t%s /* Frameworks */,' % test_frameworks_phase)
L('\t\t\t);')
L('\t\t\tbuildRules = (')
L('\t\t\t);')
L('\t\t\tdependencies = (')
L('\t\t\t\t%s /* PBXTargetDependency */,' % test_target_dependency)
L('\t\t\t);')
L('\t\t\tname = %sTests;' % PROJ)
L('\t\t\tproductName = %sTests;' % PROJ)
L('\t\t\tproductReference = %s /* %sTests.xctest */;' % (test_prod_ref, PROJ))
L('\t\t\tproductType = "com.apple.product-type.bundle.unit-test";')
L('\t\t};')

L('\t\t%s /* %sUITests */ = {' % (uitest_target, PROJ))
L('\t\t\tisa = PBXNativeTarget;')
L('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "%sUITests" */;' % (uitest_cfg_list, PROJ))
L('\t\t\tbuildPhases = (')
L('\t\t\t\t%s /* Sources */,' % uitest_sources_phase)
L('\t\t\t\t%s /* Frameworks */,' % uitest_frameworks_phase)
L('\t\t\t);')
L('\t\t\tbuildRules = (')
L('\t\t\t);')
L('\t\t\tdependencies = (')
L('\t\t\t\t%s /* PBXTargetDependency */,' % uitest_target_dependency)
L('\t\t\t);')
L('\t\t\tname = %sUITests;' % PROJ)
L('\t\t\tproductName = %sUITests;' % PROJ)
L('\t\t\tproductReference = %s /* %sUITests.xctest */;' % (uitest_prod_ref, PROJ))
L('\t\t\tproductType = "com.apple.product-type.bundle.ui-testing";')
L('\t\t};')

for ext in EXTENSION_TARGETS:
    child_embeds = EMBEDS_BY_HOST.get(ext["key"], [])
    L('\t\t%s /* %s */ = {' % (ext["target_uid"], ext["name"]))
    L('\t\t\tisa = PBXNativeTarget;')
    L('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "%s" */;' % (ext["cfg_list"], ext["name"]))
    L('\t\t\tbuildPhases = (')
    L('\t\t\t\t%s /* Sources */,' % ext["sources_phase"])
    L('\t\t\t\t%s /* Frameworks */,' % ext["frameworks_phase"])
    L('\t\t\t\t%s /* Resources */,' % ext["resources_phase"])
    for child in child_embeds:
        L('\t\t\t\t%s /* %s */,' % (child["embed_phase_uid"], child["embed_phase_name"]))
    L('\t\t\t);')
    L('\t\t\tbuildRules = (')
    L('\t\t\t);')
    L('\t\t\tdependencies = (')
    for child in child_embeds:
        L('\t\t\t\t%s /* PBXTargetDependency */,' % child["target_dependency"])
    L('\t\t\t);')
    L('\t\t\tname = "%s";' % ext["name"])
    L('\t\t\tproductName = "%s";' % ext["name"])
    L('\t\t\tproductReference = %s /* %s.%s */;' % (ext["prod_ref"], ext["name"], ext["product_ext"]))
    L('\t\t\tproductType = "%s";' % ext["product_type"])
    L('\t\t};')
L("/* End PBXNativeTarget section */")

# ---- PBXProject ---------------------------------------------------------------
L("\n/* Begin PBXProject section */")
L('\t\t%s /* Project object */ = {' % project_uid)
L('\t\t\tisa = PBXProject;')
L('\t\t\tattributes = {')
L('\t\t\t\tBuildIndependentTargetsInParallel = 1;')
L('\t\t\t\tLastSwiftUpdateCheck = 1620;')
L('\t\t\t\tLastUpgradeCheck = 1620;')
L('\t\t\t\tTargetAttributes = {')
L('\t\t\t\t\t%s = {' % app_target)
L('\t\t\t\t\t\tCreatedOnToolsVersion = 16.2;')
L('\t\t\t\t\t};')
L('\t\t\t\t\t%s = {' % test_target)
L('\t\t\t\t\t\tCreatedOnToolsVersion = 16.2;')
L('\t\t\t\t\t\tTestTargetID = %s;' % app_target)
L('\t\t\t\t\t};')
L('\t\t\t\t\t%s = {' % uitest_target)
L('\t\t\t\t\t\tCreatedOnToolsVersion = 16.2;')
L('\t\t\t\t\t\tTestTargetID = %s;' % app_target)
L('\t\t\t\t\t};')
for ext in EXTENSION_TARGETS:
    L('\t\t\t\t\t%s = {' % ext["target_uid"])
    L('\t\t\t\t\t\tCreatedOnToolsVersion = 16.2;')
    L('\t\t\t\t\t};')
L('\t\t\t\t};')
L('\t\t\t};')
L('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject "%s" */;' % (proj_cfg_list, PROJ))
L('\t\t\tcompatibilityVersion = "Xcode 14.0";')
L('\t\t\tdevelopmentRegion = fr;')
L('\t\t\thasScannedForEncodings = 0;')
L('\t\t\tknownRegions = (')
for region in ["fr", "en", "es", "de", "pt", "Base"]:
    L('\t\t\t\t%s,' % region)
L('\t\t\t);')
L('\t\t\tmainGroup = %s;' % main_group)
L('\t\t\tpackageReferences = (')
for name in pkg_refs:
    L('\t\t\t\t%s /* XCRemoteSwiftPackageReference "%s" */,' % (pkg_refs[name], name))
L('\t\t\t);')
L('\t\t\tproductRefGroup = %s /* Products */;' % products_group)
L('\t\t\tprojectDirPath = "";')
L('\t\t\tprojectRoot = "";')
L('\t\t\ttargets = (')
L('\t\t\t\t%s /* %s */,' % (app_target, PROJ))
L('\t\t\t\t%s /* %sTests */,' % (test_target, PROJ))
L('\t\t\t\t%s /* %sUITests */,' % (uitest_target, PROJ))
for ext in EXTENSION_TARGETS:
    L('\t\t\t\t%s /* %s */,' % (ext["target_uid"], ext["name"]))
L('\t\t\t);')
L('\t\t};')
L("/* End PBXProject section */")

# ---- PBXContainerItemProxy / PBXTargetDependency -----------------------------
L("\n/* Begin PBXContainerItemProxy section */")
L('\t\t%s /* PBXContainerItemProxy */ = {' % test_container_proxy)
L('\t\t\tisa = PBXContainerItemProxy;')
L('\t\t\tcontainerPortal = %s /* Project object */;' % project_uid)
L('\t\t\tproxyType = 1;')
L('\t\t\tremoteGlobalIDString = %s;' % app_target)
L('\t\t\tremoteInfo = %s;' % PROJ)
L('\t\t};')
L('\t\t%s /* PBXContainerItemProxy */ = {' % uitest_container_proxy)
L('\t\t\tisa = PBXContainerItemProxy;')
L('\t\t\tcontainerPortal = %s /* Project object */;' % project_uid)
L('\t\t\tproxyType = 1;')
L('\t\t\tremoteGlobalIDString = %s;' % app_target)
L('\t\t\tremoteInfo = %s;' % PROJ)
L('\t\t};')
for ext in EXTENSION_TARGETS:
    L('\t\t%s /* PBXContainerItemProxy */ = {' % ext["container_proxy"])
    L('\t\t\tisa = PBXContainerItemProxy;')
    L('\t\t\tcontainerPortal = %s /* Project object */;' % project_uid)
    L('\t\t\tproxyType = 1;')
    L('\t\t\tremoteGlobalIDString = %s;' % ext["target_uid"])
    L('\t\t\tremoteInfo = "%s";' % ext["name"])
    L('\t\t};')
L("/* End PBXContainerItemProxy section */")

L("\n/* Begin PBXTargetDependency section */")
L('\t\t%s /* PBXTargetDependency */ = {' % test_target_dependency)
L('\t\t\tisa = PBXTargetDependency;')
L('\t\t\ttarget = %s /* %s */;' % (app_target, PROJ))
L('\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;' % test_container_proxy)
L('\t\t};')
L('\t\t%s /* PBXTargetDependency */ = {' % uitest_target_dependency)
L('\t\t\tisa = PBXTargetDependency;')
L('\t\t\ttarget = %s /* %s */;' % (app_target, PROJ))
L('\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;' % uitest_container_proxy)
L('\t\t};')
for ext in EXTENSION_TARGETS:
    L('\t\t%s /* PBXTargetDependency */ = {' % ext["target_dependency"])
    L('\t\t\tisa = PBXTargetDependency;')
    L('\t\t\ttarget = %s /* %s */;' % (ext["target_uid"], ext["name"]))
    L('\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;' % ext["container_proxy"])
    L('\t\t};')
L("/* End PBXTargetDependency section */")

if SPM_PACKAGES:
    L("\n/* Begin XCRemoteSwiftPackageReference section */")
    for name, url, version, products in SPM_PACKAGES:
        L('\t\t%s /* XCRemoteSwiftPackageReference "%s" */ = {' % (pkg_refs[name], name))
        L('\t\t\tisa = XCRemoteSwiftPackageReference;')
        L('\t\t\trepositoryURL = "%s";' % url)
        L('\t\t\trequirement = {')
        L('\t\t\t\tkind = exactVersion;')
        L('\t\t\t\tversion = %s;' % version)
        L('\t\t\t};')
        L('\t\t};')
    L("/* End XCRemoteSwiftPackageReference section */")

    L("\n/* Begin XCSwiftPackageProductDependency section */")
    for name, url, version, products in SPM_PACKAGES:
        for prod in products:
            L('\t\t%s /* %s */ = {' % (product_deps[prod], prod))
            L('\t\t\tisa = XCSwiftPackageProductDependency;')
            L('\t\t\tpackage = %s /* XCRemoteSwiftPackageReference "%s" */;' % (pkg_refs[name], name))
            L('\t\t\tproductName = %s;' % prod)
            L('\t\t};')
    L("/* End XCSwiftPackageProductDependency section */")

# ---- PBXResourcesBuildPhase ---------------------------------------------------
L("\n/* Begin PBXResourcesBuildPhase section */")
L('\t\t%s /* Resources */ = {' % resources_phase)
L('\t\t\tisa = PBXResourcesBuildPhase;')
L('\t\t\tbuildActionMask = 2147483647;')
L('\t\t\tfiles = (')
L('\t\t\t\t%s /* Assets.xcassets in Resources */,' % assets_build_file)
L('\t\t\t\t%s /* Localizable.xcstrings in Resources */,' % xcstrings_build_file)
L('\t\t\t\t%s /* MileageRules in Resources */,' % rules_build_file)
L('\t\t\t\t%s /* PrivacyInfo.xcprivacy in Resources */,' % privacy_build_file)
L('\t\t\t);')
L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
L('\t\t};')
for ext in EXTENSION_TARGETS:
    L('\t\t%s /* Resources */ = {' % ext["resources_phase"])
    L('\t\t\tisa = PBXResourcesBuildPhase;')
    L('\t\t\tbuildActionMask = 2147483647;')
    L('\t\t\tfiles = (')
    # Every extension also gets the shared String Catalog, so localized strings resolve
    # the same way in widgets/complications as in the app (falls back to the raw key for
    # any string that genuinely is app-only).
    L('\t\t\t\t%s /* Localizable.xcstrings in Resources */,' % ext["xcstrings_build_file"])
    if ext["own_assets"]:
        L('\t\t\t\t%s /* Assets.xcassets in Resources */,' % ext["assets_build_file"])
    L('\t\t\t);')
    L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
    L('\t\t};')
L("/* End PBXResourcesBuildPhase section */")

# ---- PBXSourcesBuildPhase ------------------------------------------------------
L("\n/* Begin PBXSourcesBuildPhase section */")
L('\t\t%s /* Sources */ = {' % sources_phase)
L('\t\t\tisa = PBXSourcesBuildPhase;')
L('\t\t\tbuildActionMask = 2147483647;')
L('\t\t\tfiles = (')
for f in app_swift_files:
    L('\t\t\t\t%s /* %s in Sources */,' % (app_build_files[f], os.path.basename(f)))
L('\t\t\t);')
L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
L('\t\t};')
L('\t\t%s /* Sources */ = {' % test_sources_phase)
L('\t\t\tisa = PBXSourcesBuildPhase;')
L('\t\t\tbuildActionMask = 2147483647;')
L('\t\t\tfiles = (')
for f in test_swift_files:
    L('\t\t\t\t%s /* %s in Sources */,' % (test_build_files[f], os.path.basename(f)))
L('\t\t\t);')
L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
L('\t\t};')
L('\t\t%s /* Sources */ = {' % uitest_sources_phase)
L('\t\t\tisa = PBXSourcesBuildPhase;')
L('\t\t\tbuildActionMask = 2147483647;')
L('\t\t\tfiles = (')
for f in uitest_swift_files:
    L('\t\t\t\t%s /* %s in Sources */,' % (uitest_build_files[f], os.path.basename(f)))
L('\t\t\t);')
L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
L('\t\t};')
for ext in EXTENSION_TARGETS:
    L('\t\t%s /* Sources */ = {' % ext["sources_phase"])
    L('\t\t\tisa = PBXSourcesBuildPhase;')
    L('\t\t\tbuildActionMask = 2147483647;')
    L('\t\t\tfiles = (')
    for f in ext["swift_files"]:
        L('\t\t\t\t%s /* %s in Sources */,' % (ext["build_files"][f], os.path.basename(f)))
    L('\t\t\t);')
    L('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
    L('\t\t};')
L("/* End PBXSourcesBuildPhase section */")

# ---- XCBuildConfiguration -------------------------------------------------------
def proj_common():
    return [
        'ALWAYS_SEARCH_USER_PATHS = NO;',
        'CLANG_ANALYZER_NONNULL = YES;',
        'CLANG_ENABLE_MODULES = YES;',
        'CLANG_ENABLE_OBJC_ARC = YES;',
        'ENABLE_STRICT_OBJC_MSGSEND = YES;',
        'GCC_C_LANGUAGE_STANDARD = gnu17;',
        'GCC_NO_COMMON_BLOCKS = YES;',
        'MTL_FAST_MATH = YES;',
        'SDKROOT = iphoneos;',
        'SWIFT_EMIT_LOC_STRINGS = YES;',
    ]


def app_target_common():
    return [
        'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;',
        'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;',
        'CODE_SIGN_ENTITLEMENTS = "%s";' % entitlements_path,
        'ENABLE_PREVIEWS = YES;',
        'GENERATE_INFOPLIST_FILE = NO;',
        'INFOPLIST_FILE = "%s";' % info_plist_path,
        'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");',
        'PRODUCT_BUNDLE_IDENTIFIER = "%s";' % BUNDLE_ID_VAR,
        'PRODUCT_NAME = "$(TARGET_NAME)";',
        'TARGETED_DEVICE_FAMILY = "1";',
    ]


def test_target_common():
    return [
        'BUNDLE_LOADER = "$(TEST_HOST)";',
        'GENERATE_INFOPLIST_FILE = YES;',
        'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks");',
        'PRODUCT_BUNDLE_IDENTIFIER = "%s.tests";' % BUNDLE_ID_VAR,
        'PRODUCT_NAME = "$(TARGET_NAME)";',
        'TARGETED_DEVICE_FAMILY = "1";',
        'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/%s.app/%s";' % (PROJ, PROJ),
    ]


def uitest_target_common():
    return [
        'GENERATE_INFOPLIST_FILE = YES;',
        'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks");',
        'PRODUCT_BUNDLE_IDENTIFIER = "%s.uitests";' % BUNDLE_ID_VAR,
        'PRODUCT_NAME = "$(TARGET_NAME)";',
        'TARGETED_DEVICE_FAMILY = "1";',
        'TEST_TARGET_NAME = %s;' % PROJ,
    ]


def ext_target_common(ext):
    settings = [
        'CODE_SIGN_ENTITLEMENTS = "%s";' % ext["entitlements"],
        'GENERATE_INFOPLIST_FILE = NO;',
        'INFOPLIST_FILE = "%s";' % ext["info_plist"],
        'INFOPLIST_KEY_CFBundleDisplayName = "%s";' % ext["name"],
        'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks");',
        'PRODUCT_BUNDLE_IDENTIFIER = "%s%s";' % (BUNDLE_ID_VAR, ext["bundle_id_suffix"]),
        'PRODUCT_NAME = "$(TARGET_NAME)";',
        'SDKROOT = %s;' % ext["sdkroot"],
        'SKIP_INSTALL = YES;',
        'TARGETED_DEVICE_FAMILY = "%s";' % ext["device_family"],
        '%s = %s;' % ext["deployment_target"],
    ]
    settings += ext.get("extra_settings", [])
    return settings


ENVIRONMENTS = [("Debug", "Debug.xcconfig"), ("Release", "Release.xcconfig")]

L("\n/* Begin XCBuildConfiguration section */")
for env_name, xcconfig_name in ENVIRONMENTS:
    cfg_uid = uid("cfg.proj." + env_name)
    L('\t\t%s /* %s */ = {' % (cfg_uid, env_name))
    L('\t\t\tisa = XCBuildConfiguration;')
    L('\t\t\tbaseConfigurationReference = %s /* %s */;' % (xcconfig_refs[xcconfig_name], xcconfig_name))
    L('\t\t\tbuildSettings = {')
    for s in proj_common():
        L('\t\t\t\t' + s)
    if env_name == "Debug":
        L('\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;')
        L('\t\t\t\tENABLE_TESTABILITY = YES;')
        L('\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;')
        L('\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");')
        L('\t\t\t\tONLY_ACTIVE_ARCH = YES;')
        L('\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";')
        L('\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";')
    else:
        L('\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
        L('\t\t\t\tENABLE_NS_ASSERTIONS = NO;')
        L('\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;')
    L('\t\t\t};')
    L('\t\t\tname = %s;' % env_name)
    L('\t\t};')

for env_name, _ in ENVIRONMENTS:
    cfg_uid = uid("cfg.app." + env_name)
    L('\t\t%s /* %s */ = {' % (cfg_uid, env_name))
    L('\t\t\tisa = XCBuildConfiguration;')
    L('\t\t\tbuildSettings = {')
    for s in app_target_common():
        L('\t\t\t\t' + s)
    L('\t\t\t};')
    L('\t\t\tname = %s;' % env_name)
    L('\t\t};')

for env_name, _ in ENVIRONMENTS:
    cfg_uid = uid("cfg.tests." + env_name)
    L('\t\t%s /* %s */ = {' % (cfg_uid, env_name))
    L('\t\t\tisa = XCBuildConfiguration;')
    L('\t\t\tbuildSettings = {')
    for s in test_target_common():
        L('\t\t\t\t' + s)
    L('\t\t\t};')
    L('\t\t\tname = %s;' % env_name)
    L('\t\t};')

for env_name, _ in ENVIRONMENTS:
    cfg_uid = uid("cfg.uitests." + env_name)
    L('\t\t%s /* %s */ = {' % (cfg_uid, env_name))
    L('\t\t\tisa = XCBuildConfiguration;')
    L('\t\t\tbuildSettings = {')
    for s in uitest_target_common():
        L('\t\t\t\t' + s)
    L('\t\t\t};')
    L('\t\t\tname = %s;' % env_name)
    L('\t\t};')

for ext in EXTENSION_TARGETS:
    for env_name, _ in ENVIRONMENTS:
        cfg_uid = uid("cfg." + ext["key"] + "." + env_name)
        L('\t\t%s /* %s */ = {' % (cfg_uid, env_name))
        L('\t\t\tisa = XCBuildConfiguration;')
        L('\t\t\tbuildSettings = {')
        for s in ext_target_common(ext):
            L('\t\t\t\t' + s)
        L('\t\t\t};')
        L('\t\t\tname = %s;' % env_name)
        L('\t\t};')
L("/* End XCBuildConfiguration section */")

# ---- XCConfigurationList --------------------------------------------------------
L("\n/* Begin XCConfigurationList section */")
def emit_cfg_list(list_uid, comment, prefix):
    L('\t\t%s /* %s */ = {' % (list_uid, comment))
    L('\t\t\tisa = XCConfigurationList;')
    L('\t\t\tbuildConfigurations = (')
    for env_name, _ in ENVIRONMENTS:
        L('\t\t\t\t%s /* %s */,' % (uid(prefix + env_name), env_name))
    L('\t\t\t);')
    L('\t\t\tdefaultConfigurationIsVisible = 0;')
    L('\t\t\tdefaultConfigurationName = Release;')
    L('\t\t};')

emit_cfg_list(proj_cfg_list, 'Build configuration list for PBXProject "%s"' % PROJ, "cfg.proj.")
emit_cfg_list(app_cfg_list, 'Build configuration list for PBXNativeTarget "%s"' % PROJ, "cfg.app.")
emit_cfg_list(test_cfg_list, 'Build configuration list for PBXNativeTarget "%sTests"' % PROJ, "cfg.tests.")
emit_cfg_list(uitest_cfg_list, 'Build configuration list for PBXNativeTarget "%sUITests"' % PROJ, "cfg.uitests.")
for ext in EXTENSION_TARGETS:
    emit_cfg_list(ext["cfg_list"], 'Build configuration list for PBXNativeTarget "%s"' % ext["name"], "cfg." + ext["key"] + ".")
L("/* End XCConfigurationList section */")

L("\t};")
L('\trootObject = %s /* Project object */;' % project_uid)
L("}")

out_dir = os.path.join(ROOT, "%s.xcodeproj" % PROJ)
os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, "project.pbxproj"), "w") as fh:
    fh.write("\n".join(lines) + "\n")

# ---- Shared scheme --------------------------------------------------------
# Without this, a from-source project has no persisted scheme for headless
# `xcodebuild -scheme Pillo ...` to find (Xcode only auto-derives one once you've
# opened the project in the GUI at least once) — write it explicitly instead.
def buildable_ref(blueprint_id, name):
    return (
        '            <BuildableReference\n'
        '               BuildableIdentifier = "primary"\n'
        '               BlueprintIdentifier = "%s"\n'
        '               BuildableName = "%s"\n'
        '               BlueprintName = "%s"\n'
        '               ReferencedContainer = "container:%s.xcodeproj">\n'
        '            </BuildableReference>\n'
    ) % (blueprint_id, name, name.rsplit(".", 1)[0], PROJ)


scheme_xml = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<Scheme LastUpgradeVersion = "1620" version = "1.7">\n'
    '   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">\n'
    '      <BuildActionEntries>\n'
    '         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">\n'
    + buildable_ref(app_target, PROJ + ".app") +
    '         </BuildActionEntry>\n'
    '         <BuildActionEntry buildForTesting = "YES" buildForRunning = "NO" buildForProfiling = "NO" buildForArchiving = "NO" buildForAnalyzing = "YES">\n'
    + buildable_ref(test_target, PROJ + "Tests.xctest") +
    '         </BuildActionEntry>\n'
    '         <BuildActionEntry buildForTesting = "YES" buildForRunning = "NO" buildForProfiling = "NO" buildForArchiving = "NO" buildForAnalyzing = "YES">\n'
    + buildable_ref(uitest_target, PROJ + "UITests.xctest") +
    '         </BuildActionEntry>\n'
    '      </BuildActionEntries>\n'
    '   </BuildAction>\n'
    '   <TestAction\n'
    '      buildConfiguration = "Debug"\n'
    '      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"\n'
    '      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"\n'
    '      shouldUseLaunchSchemeArgsEnv = "YES">\n'
'      <StoreKitConfigurationFileReference\n         identifier = "../../../Config/MileagePocket.storekit">\n      </StoreKitConfigurationFileReference>\n'
    '      <Testables>\n'
    '         <TestableReference skipped = "NO">\n'
    + buildable_ref(test_target, PROJ + "Tests.xctest") +
    '         </TestableReference>\n'
    '         <TestableReference skipped = "NO">\n'
    + buildable_ref(uitest_target, PROJ + "UITests.xctest") +
    '         </TestableReference>\n'
    '      </Testables>\n'
    '   </TestAction>\n'
    '   <LaunchAction\n'
    '      buildConfiguration = "Debug"\n'
    '      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"\n'
    '      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"\n'
    '      launchStyle = "0"\n'
    '      useCustomWorkingDirectory = "NO"\n'
    '      ignoresPersistentStateOnLaunch = "NO"\n'
    '      debugDocumentVersioning = "YES"\n'
    '      debugServiceExtension = "internal"\n'
    '      allowLocationSimulation = "YES">\n'
'      <StoreKitConfigurationFileReference\n         identifier = "../../../Config/MileagePocket.storekit">\n      </StoreKitConfigurationFileReference>\n'
    '      <BuildableProductRunnable runnableDebuggingMode = "0">\n'
    + buildable_ref(app_target, PROJ + ".app") +
    '      </BuildableProductRunnable>\n'
    '   </LaunchAction>\n'
    '   <ArchiveAction\n'
    '      buildConfiguration = "Release"\n'
    '      revealArchiveInOrganizer = "YES">\n'
    '   </ArchiveAction>\n'
    '</Scheme>\n'
)

scheme_dir = os.path.join(out_dir, "xcshareddata", "xcschemes")
os.makedirs(scheme_dir, exist_ok=True)
with open(os.path.join(scheme_dir, f"{PROJ}.xcscheme"), "w") as fh:
    fh.write(scheme_xml)

ext_summary = ", ".join(f"{e['name']}: {len(e['swift_files'])}" for e in EXTENSION_TARGETS)
print(f"Wrote {out_dir}/project.pbxproj — app: {len(app_swift_files)} files (incl. {len(shared_files)} shared), tests: {len(test_swift_files)}, uitests: {len(uitest_swift_files)}, {ext_summary}")
