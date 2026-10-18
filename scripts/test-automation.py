#!/usr/bin/env python3
"""After make build, exercise the app controller in an isolated macOS bundle."""
import json
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
tour = "--tour" in sys.argv
harness = "TourHarness" if tour else "AutomationHarness"
products = root / ".build/xcode/Build/Products/Debug"
assert (products / "BattisticsCore.o").exists(), "Run make build first"
with tempfile.TemporaryDirectory(prefix="battistics-qa-") as temporary:
    bundle = Path(temporary) / "BattisticsAutomationQA.app"
    executable = bundle / "Contents/MacOS/BattisticsAutomationQA"
    executable.parent.mkdir(parents=True)
    resources = bundle / "Contents/Resources"
    resources.mkdir()
    plist = {
        "CFBundleIdentifier": "com.doguyilmaz.Battistics.AutomationQA",
        "CFBundleExecutable": executable.name, "CFBundleName": "Battistics Automation QA",
        "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "tr"],
        "LSUIElement": True,
    }
    (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(plist))
    catalog = json.loads((root / "Sources/BattisticsApp/Resources/Localizable.xcstrings").read_text())
    for language in ["en", "tr"]:
        folder = resources / f"{language}.lproj"
        folder.mkdir()
        strings = {key: entry.get("localizations", {}).get(language, {}).get("stringUnit", {}).get("value", key)
                   for key, entry in catalog["strings"].items()}
        (folder / "Localizable.strings").write_bytes(plistlib.dumps(strings, fmt=plistlib.FMT_BINARY))
    sources = [str(p) for p in (root / "Sources/BattisticsApp").rglob("*.swift") if p.name != "BattisticsApp.swift"]
    subprocess.run([
        "swiftc", "-parse-as-library", "-swift-version", "6",
        "-module-name", "BattisticsAutomationQA", "-I", str(products), "-F", str(products),
        "-framework", "Sparkle", "-lsqlite3", "-Xlinker", "-rpath", "-Xlinker", str(products),
        str(products / "BattisticsCore.o"), *sources, str(root / f"Tests/Integration/{harness}.swift"),
        "-o", str(executable),
    ], cwd=root, check=True)
    for language in ["en", "tr"]:
        subprocess.run([str(executable), "-AppleLanguages", f"({language})"], check=True, timeout=60)
