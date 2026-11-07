"""Exercise the production offsets loader without Roblox or network access."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--luau", required=True, type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
source = (repo / "autofarm_normal.lua").read_text(encoding="utf-8")
start = source.index('local function GetOffsets(): OffsetsData?')
end = source.index('end; local OffsetsFake = GetOffsets()', start) + 3
production = source[start:end].replace(': string?', '').replace(': OffsetsData?', '').replace(' :: OffsetsData', '')
gradient_start = source.index('    if not Supplies.VersionChecked then')
gradient_end = source.index('    if gradient and gradient.ClassName', gradient_start)
gradient_selection = source[gradient_start:gradient_end]
fixture = '''
local version = "version-f0ea5da9412f4e35"
local warnings, boots = {}, {}
local function getrbxversion() return version end
local function forbidden() error("bundled offsets must not use network or cache") end
local httpget, readfile, writefile, isfile = forbidden, forbidden, forbidden, forbidden
local game = {HttpGet=forbidden}
local function Boot(s) table.insert(boots,s) end
local function warn(s) table.insert(warnings,s) end
'''
checks = '''
version = "version-f0ea5da9412f4e35"
local bundled = assert(GetOffsets(), "supported client must start offline with no cache")
assert(#warnings == 0)
assert(bundled.Offsets.Model.PrimaryPart == 576)
assert(bundled.Offsets.BasePart.Primitive == 376)
assert(bundled.Offsets.Primitive.Position == 212)
assert(bundled.Offsets.GuiObject.Visible == 1397 and bundled.Offsets.GuiObject.Size == 1272)
assert(bundled.Offsets.GuiBase2D.AbsoluteSize == 0)
assert(bundled.Offsets.Humanoid.HumanoidState == 2216)
assert(bundled.Offsets.Humanoid.HumanoidStateID == 32)
version = "version-11f155f3450f4c8e"
local archived = assert(GetOffsets(), "archived client must select its own layout offline")
assert(archived.Offsets.Model.PrimaryPart == 584)
assert(archived.Offsets.BasePart.Primitive == 384)
assert(archived.Offsets.Primitive.Position == 212)
assert(archived.Offsets.GuiObject.Visible == 1437 and archived.Offsets.GuiObject.Size == 1312)
assert(archived.Offsets.GuiBase2D.AbsoluteSize == 260)
assert(archived.Offsets.Humanoid.HumanoidState == 2224)
assert(archived.Offsets.Humanoid.HumanoidStateID == 32)
assert(#warnings == 0)
version = "version-unknown"
assert(GetOffsets() == nil, "unknown client must not use bundled layout")
assert(string.find(warnings[#warnings], version, 1, true), "warning must identify unsupported version")
for _, invalid in ipairs({false, 123, ""}) do
  version = invalid
  assert(GetOffsets() == nil, "invalid client version must stop startup")
end
getrbxversion = nil
assert(GetOffsets() == nil, "missing version API must stop startup")
getrbxversion = function() error("version unavailable") end
assert(GetOffsets() == nil, "failing version API must stop startup")
assert(string.find(warnings[#warnings], "cannot read", 1, true))
print("PASS: bundled offsets start offline; unknown/invalid versions and unavailable version API stop safely")
'''
gradient_checks = '''
local function gradientOffset(client)
  version = client
  local Supplies = {}
''' + gradient_selection + '''
  return Supplies.GradientOffset
end
assert(gradientOffset("version-f0ea5da9412f4e35") == 296)
assert(gradientOffset("version-11f155f3450f4c8e") == 304)
assert(gradientOffset("version-unknown") == nil)
print("PASS: HUD gradient offsets match each supported client")
'''
with tempfile.TemporaryDirectory(prefix="aotr-startup-") as directory:
    script = Path(directory) / "startup.luau"
    script.write_text(fixture + production + gradient_checks + checks, encoding="utf-8")
    result = subprocess.run([str(args.luau.resolve()), str(script)], check=False)
    raise SystemExit(result.returncode)
