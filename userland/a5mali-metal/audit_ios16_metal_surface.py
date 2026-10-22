#!/usr/bin/env python3
"""Compare the vended Metal objects with an *external* iOS 16 ObjC dump.

The dump is intentionally not distributed with this repository.  This checks
selector availability and coarse calling convention only.  A present method
may still reject a feature, so this is not a GPU capability test.
"""

import argparse
import hashlib
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
BASELINE = HERE / "ios16_metal_surface_baseline.json"

# Only protocols actually present in the pinned iOS 16 Metal image are used.
# Command-queue and render/blit/compute-encoder protocols are not in that image.
OBJECTS = {
    "A5MaliMetalDevice": "MTLDeviceSPI",
    "A5MaliMetalBuffer": "MTLCommandBuffer",
    "A5MaliMetalRenderEncoder": "MTLCommandEncoder",
    "A5MaliMetalBlitEncoder": "MTLCommandEncoder",
    "A5MaliMetalTexture": "MTLTexture",
    "A5MaliPrivateBuffer": "MTLBuffer",
    "A5MaliSharedReadBuffer": "MTLBuffer",
    "A5MaliMetalLibrary": "MTLLibrary",
    "A5MaliMetalFunction": "MTLFunction",
    "A5MaliCompiledPipeline": "MTLRenderPipelineState",
    "A5MaliSamplerState": "MTLSamplerState",
    "A5MaliDepthStencilState": "MTLDepthStencilState",
}

# The provider does not claim these SPI protocols, but stock iOS code may
# message their selectors.  Report this surface separately from public gaps.
PRIVATE_OBJECTS = {
    "A5MaliMetalRenderEncoder": "MTLCommandEncoderSPI",
    "A5MaliMetalBlitEncoder": "MTLCommandEncoderSPI",
    "A5MaliMetalLibrary": "MTLLibrarySPI",
    "A5MaliMetalFunction": "MTLFunctionSPI",
    "A5MaliMetalTexture": "MTLTextureSPI",
    "A5MaliPrivateBuffer": "MTLResourceSPI",
    "A5MaliSharedReadBuffer": "MTLResourceSPI",
    "A5MaliSamplerState": "MTLSamplerStateSPI",
    "A5MaliDepthStencilState": "MTLDepthStencilStateSPI",
}


def selector(signature):
    # Remove type spans before collecting keyword pieces.  In particular,
    # the type of a block argument can itself contain colons in a protocol.
    no_types = re.sub(r"\([^()]*\)", " ", signature)
    words = re.findall(r"([A-Za-z_]\w*)\s*:", no_types)
    if words:
        return "".join(w + ":" for w in words)
    first = re.search(r"[A-Za-z_]\w*", no_types)
    return first.group() if first else None


def type_kind(t):
    t = re.sub(r"\b(const|nullable|_Nullable|__nullable|_Nonnull|__nonnull)\b", "", t).strip()
    if t == "void":
        return "void"
    if t in {"_Bool", "BOOL", "bool"}:
        return "bool"
    if "*" in t or t in {"id", "Class", "SEL", "instancetype", "dispatch_queue_t", "dispatch_data_t"} or t.startswith("id<") or t.endswith("Handler"):
        return "pointer"
    if t in {"float", "double", "CGFloat", "NSTimeInterval"}:
        return "float"
    if t.startswith("struct ") or t in {"MTLSize", "MTLSizeAndAlign", "MTLRegion", "MTLViewport", "MTLScissorRect", "MTLResourceID", "MTLTextureSwizzleChannels"}:
        return "aggregate"
    # Signedness of a 64-bit enum is a type-encoding difference, not a
    # different arm64 calling convention.  This audit checks calling shape.
    if re.search(r"\b(unsigned|NSUInteger|NSInteger|uint64_t|int64_t|MTL\w+)\b", t) or "long long" in t:
        return "integral64"
    if re.search(r"\b(uint32_t|int32_t|int)\b", t):
        return "integral32"
    return "unknown"


def method_abi(signature):
    result = re.match(r"\s*-\s*\(([^)]*)\)", signature)
    if not result:
        return ("unknown", [])
    # Nested block signatures cannot be handled by a plain regexp. Preserve
    # unknown for those positions rather than claiming a matching ABI.
    args = [type_kind(m.group(1)) for m in re.finditer(r":\s*\(([^()]*)\)", signature)]
    return type_kind(result.group(1)), args


def method_signatures(block, marker):
    if marker not in block:
        return {}
    body = block.split(marker, 1)[1]
    body = body.split("@optional", 1)[0]
    out = {}
    for m in re.finditer(r"^\s*-\s*\([^\n]*?\)[^;{]*;", body, re.M | re.S):
        signature = " ".join(m.group().split()).rstrip(";")
        key = selector(signature)
        if key:
            out[key] = method_abi(signature)
    return out


def parse_dump(contents):
    protocols = {}
    for m in re.finditer(r"^@protocol\s+(\w+)(?:\s*<([^>]+)>)?[^\n]*\n(.*?)^@end", contents, re.M | re.S):
        name, parents, body = m.groups()
        protocols[name] = ([p.strip() for p in parents.split(",")] if parents else [],
                           method_signatures(body, "/* required instance methods */"))
    classes = {}
    for m in re.finditer(r"^@interface\s+(\w+)(?:\s*:\s*(\w+))?[^\n]*\n(.*?)^@end", contents, re.M | re.S):
        name, parent, body = m.groups()
        classes[name] = (parent, method_signatures(body, "/* instance methods */"))
    return protocols, classes


def source_methods(contents):
    out = {}
    for m in re.finditer(r"^\s*-\s*\([^\n]*?\)[^;{]*\{", contents, re.M | re.S):
        signature = " ".join(m.group().split()).rstrip("{").strip()
        key = selector(signature)
        if key:
            out[key] = method_abi(signature)
    return out


def parse_source():
    classes = {}
    for path in [*HERE.glob("*.m"), *HERE.glob("StockMetalPlugin/*.m")]:
        contents = path.read_text(errors="replace")
        for m in re.finditer(r"^@implementation\s+(\w+)(?:\s*\([^)]*\))?(.*?)(?=^@end)", contents, re.M | re.S):
            classes.setdefault(m.group(1), {}).update(source_methods(m.group(2)))
    parents = {}
    properties = {}
    for path in [*HERE.glob("*.h"), *HERE.glob("*.m"), *HERE.glob("StockMetalPlugin/*.h"), *HERE.glob("StockMetalPlugin/*.m")]:
        contents = path.read_text(errors="replace")
        for m in re.finditer(r"^@interface\s+(\w+)(?:\s*:\s*(\w+))?[^\n]*\n(.*?)^@end", contents, re.M | re.S):
            name, parent, body = m.groups()
            if parent:
                parents[name] = parent
            for p in re.finditer(r"@property\s*\(([^)]*)\)\s*([^;]+);", body):
                declaration = p.group(2).strip()
                prop = re.search(r"([A-Za-z_]\w*)\s*$", declaration)
                if not prop:
                    continue
                key = prop.group(1)
                # Automatic property synthesis supplies accessors even if no
                # explicit method definition appears in the source.
                kind = type_kind(declaration[:prop.start()].strip())
                properties.setdefault(name, {})[key] = (kind, [])
                if "readonly" not in p.group(1):
                    properties[name]["set" + key[0].upper() + key[1:] + ":"] = ("void", [kind])
    for name, props in properties.items():
        merged = classes.setdefault(name, {})
        for key, kind in props.items():
            merged.setdefault(key, kind)
    return classes, parents


def inherited(name, classes, parents):
    out = {}
    seen = set()
    while name and name not in seen:
        seen.add(name)
        out.update({k: v for k, v in classes.get(name, {}).items() if k not in out})
        name = parents.get(name)
    return out


def protocol_methods(name, protocols, seen=None):
    if seen is None:
        seen = set()
    # Every vended class descends from NSObject; its own selectors are already
    # available and need no per-provider implementation.
    if name == "NSObject" or name in seen or name not in protocols:
        return {}
    seen.add(name)
    parents, methods = protocols[name]
    out = {}
    for parent in parents:
        out.update(protocol_methods(parent, protocols, seen))
    out.update(methods)
    return out


def audit(dump):
    protocols, stock = parse_dump(dump)
    classes, parents = parse_source()
    # _MTLDevice is the actual iOS superclass, unlike a locally invented
    # NSObject slice. Its methods count as available but *not* as native Mali
    # support. Keep their provenance separate in the report.
    stock_parent, stock_methods = stock.get("_MTLDevice", (None, {}))
    if not stock_methods:
        raise ValueError("iOS dump lacks _MTLDevice method list")
    def scan(group):
      result = {}
      for concrete, protocol in group.items():
        required = protocol_methods(protocol, protocols)
        if not required:
            raise ValueError("iOS dump lacks " + protocol)
        source = inherited(concrete, classes, parents)
        super_methods = stock_methods if concrete == "A5MaliMetalDevice" else {}
        missing = sorted(set(required) - set(source) - set(super_methods))
        stock_only = sorted((set(required) & set(super_methods)) - set(source))
        type_gaps = {}
        argument_gaps = {}
        for key in set(required) & set(source):
            (want, want_args), (got, got_args) = required[key], source[key]
            if want != "unknown" and got != "unknown" and want != got:
                type_gaps[key] = [want, got]
            if len(want_args) == key.count(":") == len(got_args):
                differences = [[i, a, b] for i, (a, b) in enumerate(zip(want_args, got_args))
                               if a != "unknown" and b != "unknown" and a != b]
                if differences:
                    argument_gaps[key] = differences
        result[concrete] = {
            "protocol": protocol,
            "required_count": len(required),
            "missing": missing,
            "stock_superclass_only": stock_only,
            "result_kind_mismatches": dict(sorted(type_gaps.items())),
            "argument_kind_mismatches": dict(sorted(argument_gaps.items())),
        }
      return result
    return scan(OBJECTS), scan(PRIVATE_OBJECTS)


def sdk_surrogate(sdk_headers):
    """Informational only: installed SDK may be newer than the target OS."""
    classes, parents = parse_source()
    lookup = {
        "MTLCommandQueue": ("MTLCommandQueue.h", "A5MaliMetalQueue"),
        "MTLRenderCommandEncoder": ("MTLRenderCommandEncoder.h", "A5MaliMetalRenderEncoder"),
        "MTLBlitCommandEncoder": ("MTLBlitCommandEncoder.h", "A5MaliMetalBlitEncoder"),
    }
    result = {}
    for protocol, (header, concrete) in lookup.items():
        contents = (sdk_headers / header).read_text()
        block = re.search(r"^@protocol\s+" + protocol + r"\s*<[^>]+>(.*?)^@end",
                          contents, re.M | re.S)
        if not block:
            raise ValueError("SDK header lacks " + protocol)
        body = re.sub(r"/\*.*?\*/",
                      lambda m: re.sub(r"[^\n]", " ", m.group()),
                      block.group(1), flags=re.S).split("@optional", 1)[0]
        declared = {}
        for m in re.finditer(r"^\s*-\s*\([^;{]*?;", body, re.M | re.S):
            signature = " ".join(m.group().split())
            if re.search(r"\bAPI_UNAVAILABLE\([^)]*\bios\b", signature):
                continue
            availability = re.search(r"API_AVAILABLE\([^;]*?ios\((\d+)", signature)
            if availability and int(availability.group(1)) > 16:
                continue
            # Availability/deprecation macros can contain selector-looking
            # replacement strings; only the declaration before them counts.
            declaration = re.split(r"\b(?:API_|NS_SWIFT_NAME|NS_REFINED_FOR_SWIFT)",
                                   signature, maxsplit=1)[0]
            key = selector(declaration)
            if key:
                declared[key] = {
                    "signature": signature,
                    "header": header,
                    "line": contents.count("\n", 0, block.start(1) + m.start()) + 1,
                }
        for m in re.finditer(r"@property\s*\(([^)]*)\)\s*([^;]+);", body):
            name = re.search(r"([A-Za-z_]\w*)\s*$", m.group(2))
            if name:
                key = name.group(1)
                info = {"signature": " ".join(m.group().split()), "header": header,
                        "line": contents.count("\n", 0, block.start(1) + m.start()) + 1}
                declared[key] = info
                if "readonly" not in m.group(1):
                    declared["set" + key[0].upper() + key[1:] + ":"] = info
        missing = sorted(set(declared) - set(inherited(concrete, classes, parents)))
        result[protocol] = {"declared_through_ios16": len(declared), "missing": missing,
                            "missing_detail": {key: declared[key] for key in missing}}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ios16-objc-dump", required=True, type=pathlib.Path)
    parser.add_argument("--baseline", type=pathlib.Path, default=BASELINE)
    parser.add_argument("--write-baseline", action="store_true")
    parser.add_argument("--sdk-headers", type=pathlib.Path,
                        help="optional installed SDK header directory; informational, not the iOS 16 gate")
    parser.add_argument("--sdk-surrogate-json", type=pathlib.Path,
                        help="write machine-readable installed-SDK comparison")
    parser.add_argument("--require-sdk-surrogate-zero", action="store_true",
                        help="development gate for the installed SDK comparison only")
    args = parser.parse_args()
    raw = args.ios16_objc_dump.read_bytes()
    public, private = audit(raw.decode("utf-8", "replace"))
    report = {
        "schema": 1,
        "ios16_objc_dump_sha256": hashlib.sha256(raw).hexdigest(),
        "objects": public,
        "private_spi": private,
        "unavailable_ios16_protocols": ["MTLCommandQueue", "MTLRenderCommandEncoder", "MTLBlitCommandEncoder", "MTLComputeCommandEncoder"],
    }
    if args.write_baseline:
        if args.baseline.exists():
            old = json.loads(args.baseline.read_text())
            for section in ("objects", "private_spi"):
                for name, item in report[section].items():
                    prior = old.get(section, {}).get(name, {}).get("known_gap_classification", {})
                    item["known_gap_classification"] = {
                        key: prior[key] for key in item["missing"] if key in prior
                    }
        args.baseline.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        return
    baseline = json.loads(args.baseline.read_text())
    if report["ios16_objc_dump_sha256"] != baseline["ios16_objc_dump_sha256"]:
        raise SystemExit("iOS 16 protocol dump changed; review and rebaseline")
    failures = []
    for section in ("objects", "private_spi"):
        for name, current in report[section].items():
            previous = baseline.get(section, {}).get(name)
            if not previous or current["protocol"] != previous["protocol"]:
                failures.append(name + ": unclassified object/protocol")
                continue
            categories = previous.get("known_gap_classification", {})
            unclassified = set(current["missing"]) - set(categories)
            if unclassified:
                failures.append(name + ": unclassified required selectors: " +
                                ", ".join(sorted(unclassified)))
            for field in ("missing", "stock_superclass_only"):
                unexpected = set(current[field]) - set(previous[field])
                if unexpected:
                    failures.append(name + ": new " + field + ": " + ", ".join(sorted(unexpected)))
            for field in ("result_kind_mismatches", "argument_kind_mismatches"):
                new_types = {k: v for k, v in current[field].items()
                             if previous.get(field, {}).get(k) != v}
                if new_types:
                    failures.append(name + ": new " + field + ": " + str(new_types))
    if failures:
        raise SystemExit("\n".join(failures))
    for name, item in report["objects"].items():
        print(f"{name}: {item['required_count']} required, {len(item['missing'])} missing, "
              f"{len(item['stock_superclass_only'])} stock-superclass-only, "
              f"{len(item['result_kind_mismatches'])} coarse return ABI gaps, "
              f"{len(item['argument_kind_mismatches'])} coarse argument ABI gaps")
    for name, item in report["private_spi"].items():
        print(f"SPI {name}: {item['required_count']} required, {len(item['missing'])} missing")
    print("PASS: no new unclassified iOS 16 required-selector gaps")
    if args.sdk_headers:
        surrogate = sdk_surrogate(args.sdk_headers)
        if args.sdk_surrogate_json:
            args.sdk_surrogate_json.write_text(json.dumps(surrogate,indent=2,sort_keys=True)+"\n")
        for name, item in surrogate.items():
            print(f"SDK SURROGATE {name}: {item['declared_through_ios16']} declarations, "
                  f"{len(item['missing'])} source-missing")
            if item["missing"]:
                print("  " + ", ".join(item["missing"]))
        if args.require_sdk_surrogate_zero and any(item["missing"] for item in surrogate.values()):
            raise SystemExit("installed-SDK surrogate has missing selectors")
    elif args.require_sdk_surrogate_zero:
        raise SystemExit("--require-sdk-surrogate-zero needs --sdk-headers")


if __name__ == "__main__":
    main()
