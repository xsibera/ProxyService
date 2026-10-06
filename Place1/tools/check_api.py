"""Static checks of the Luau source against Roblox's API dump.

    python3 tools/check_api.py [path/to/API-Dump.json]

Without a path it downloads the dump from the Roblox Client Tracker. Checks:
  * create("Class", { Prop = ... }) property names exist, are writable and not deprecated
  * Instance.new / IsA / FindFirstChildOfClass / FindFirstAncestorOfClass class names
  * Enum.Type.Item names
  * game:GetService("Name") names, and Service:Member / Service.Member on those services
  * Member access on variables whose class is obvious from their name (humanoid, root, ...)
"""

import json
import os
import re
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src")
DUMP_URL = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json"

# variable name -> class, for member checks
TYPED_VARS = {
	"humanoid": "Humanoid",
	"root": "Part",
	"camera": "Camera",
	"motor": "Motor6D",
	"lv": "LinearVelocity",
	"sound": "Sound",
	"emitter": "ParticleEmitter",
	"trail": "Trail",
	"light": "PointLight",
	"highlight": "Highlight",
	"billboard": "BillboardGui",
	"gui": "BillboardGui",
	"label": "TextLabel",
	"align": "AlignOrientation",
	"colorCorrection": "ColorCorrectionEffect",
	"blur": "BlurEffect",
	"bubble": "Part",
	"orb": "Part",
	"fist": "Attachment",
	"att": "Attachment",
	"attachment": "Attachment",
	"rootAttachment": "Attachment",
	"model": "Model",
	"character": "Model",
	"player": "Player",
	"torso": "Part",
	"head": "Part",
	"arm": "Part",
	"leg": "Part",
	"bannerLabel": "TextLabel",
	"comboNumber": "TextLabel",
	"comboScale": "UIScale",
	"bannerScale": "UIScale",
	"helpFrame": "Frame",
	"comboFrame": "Frame",
	"linesFrame": "Frame",
	"line": "Frame",
	"healthFill": "Frame",
	"healthChip": "Frame",
	"healthText": "TextLabel",
	"postureFill": "Frame",
	"postureFrame": "Frame",
	"hit": "RaycastResult",
	"result": "RaycastResult",
	"overlapParams": "OverlapParams",
	"raycastParams": "RaycastParams",
	"rayParams": "RaycastParams",
}

DATATYPE_MEMBERS = {
	"RaycastResult": {"Instance", "Position", "Normal", "Material", "Distance"},
	"OverlapParams": {"FilterType", "FilterDescendantsInstances", "CollisionGroup", "MaxParts", "RespectCanCollide", "BruteForceAllSlow"},
	"RaycastParams": {"FilterType", "FilterDescendantsInstances", "IgnoreWater", "CollisionGroup", "RespectCanCollide", "BruteForceAllSlow"},
}


def load_dump(path):
	if path:
		with open(path) as f:
			return json.load(f)
	with urllib.request.urlopen(DUMP_URL) as r:
		return json.loads(r.read())


class Api:
	def __init__(self, dump):
		self.classes = {c["Name"]: c for c in dump["Classes"]}
		self.enums = {e["Name"]: {i["Name"] for i in e["Items"]} for e in dump["Enums"]}

	def members(self, name):
		out = {}
		while name and name in self.classes:
			c = self.classes[name]
			for m in c["Members"]:
				out.setdefault(m["Name"], m)
			name = c.get("Superclass")
		return out

	def tags(self, name):
		return set(self.classes[name].get("Tags") or [])


def line_of(text, index):
	return text.count("\n", 0, index) + 1


def top_level_keys(body):
	"""Keys assigned at depth 1 of a `{ ... }` table constructor body (without the braces)."""
	keys = []
	depth = 0
	i = 0
	n = len(body)
	in_str = None
	while i < n:
		ch = body[i]
		if in_str:
			if ch == "\\":
				i += 2
				continue
			if ch == in_str:
				in_str = None
			i += 1
			continue
		if ch in "\"'":
			in_str = ch
		elif body.startswith("--", i):
			nl = body.find("\n", i)
			i = n if nl < 0 else nl
			continue
		elif ch in "({[":
			depth += 1
		elif ch in ")}]":
			depth -= 1
		elif depth == 0:
			m = re.match(r"([A-Za-z_]\w*)\s*=(?!=)", body[i:])
			if m and (i == 0 or not (body[i - 1].isalnum() or body[i - 1] in "_.")):
				keys.append(m.group(1))
				i += m.end()
				continue
		i += 1
	return keys


def matching_brace(text, open_index):
	depth = 0
	in_str = None
	i = open_index
	while i < len(text):
		ch = text[i]
		if in_str:
			if ch == "\\":
				i += 2
				continue
			if ch == in_str:
				in_str = None
		elif ch in "\"'":
			in_str = ch
		elif text.startswith("--", i):
			nl = text.find("\n", i)
			i = len(text) if nl < 0 else nl
			continue
		elif ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				return i
		i += 1
	return -1


def strip_comments(text):
	"""Blank out comments (keeping offsets and line numbers intact)."""
	out = list(text)
	i, n = 0, len(text)
	in_str = None
	while i < n:
		ch = text[i]
		if in_str:
			if ch == "\\":
				i += 2
				continue
			if ch == in_str or ch == "\n":
				in_str = None
			i += 1
			continue
		if ch in "\"'`":
			in_str = ch
			i += 1
			continue
		if text.startswith("--", i):
			if text.startswith("--[[", i):
				end = text.find("]]", i)
				end = n if end < 0 else end + 2
			else:
				end = text.find("\n", i)
				end = n if end < 0 else end
			for j in range(i, end):
				if out[j] != "\n":
					out[j] = " "
			i = end
			continue
		i += 1
	return "".join(out)


def check_file(api, path, problems):
	text = strip_comments(open(path).read())
	rel = os.path.relpath(path, os.path.join(HERE, ".."))

	def report(index, msg):
		problems.append("%s:%d: %s" % (rel, line_of(text, index), msg))

	# create("Class", { ... })
	for m in re.finditer(r'create\(\s*"(\w+)"\s*,?\s*(\{)?', text):
		cls = m.group(1)
		if cls not in api.classes:
			report(m.start(), "unknown class %s" % cls)
			continue
		if {"NotCreatable", "Service"} & api.tags(cls):
			report(m.start(), "class %s is not creatable" % cls)
		if not m.group(2):
			continue
		close = matching_brace(text, m.end() - 1)
		body = text[m.end() : close]
		members = api.members(cls)
		for key in top_level_keys(body):
			if key == "Parent":
				continue
			mem = members.get(key)
			if not mem:
				report(m.start(), "%s has no member %s" % (cls, key))
			elif mem["MemberType"] != "Property":
				report(m.start(), "%s.%s is a %s, not a property" % (cls, key, mem["MemberType"]))
			else:
				tags = set(mem.get("Tags") or [])
				if "ReadOnly" in tags:
					report(m.start(), "%s.%s is read-only" % (cls, key))
				if "Deprecated" in tags:
					report(m.start(), "%s.%s is deprecated" % (cls, key))
				sec = mem.get("Security")
				write = sec.get("Write") if isinstance(sec, dict) else sec
				if write not in (None, "None"):
					report(m.start(), "%s.%s needs %s to write" % (cls, key, write))

	# class name literals
	for m in re.finditer(r'(Instance\.new|IsA|FindFirstChildOfClass|FindFirstAncestorOfClass|FindFirstChildWhichIsA)\(\s*"(\w+)"', text):
		if m.group(2) not in api.classes:
			report(m.start(), "unknown class %s in %s" % (m.group(2), m.group(1)))

	# Enum.X.Y
	for m in re.finditer(r"\bEnum\.(\w+)\.(\w+)", text):
		enum, item = m.group(1), m.group(2)
		if enum not in api.enums:
			report(m.start(), "unknown enum Enum.%s" % enum)
		elif item not in api.enums[enum] and item not in ("GetEnumItems", "FromName", "FromValue"):
			report(m.start(), "Enum.%s has no item %s" % (enum, item))
	for m in re.finditer(r"\bEnum\.(\w+)\[", text):
		if m.group(1) not in api.enums:
			report(m.start(), "unknown enum Enum.%s" % m.group(1))

	# services
	service_vars = {}
	for m in re.finditer(r'(?:local\s+)?(\w+)\s*=\s*game:GetService\("(\w+)"\)', text):
		name = m.group(2)
		if name not in api.classes or "Service" not in api.tags(name):
			report(m.start(), "unknown service %s" % name)
		else:
			service_vars[m.group(1)] = name
	for m in re.finditer(r'game:GetService\("(\w+)"\)[.:](\w+)', text):
		if m.group(2) not in api.members(m.group(1)):
			report(m.start(), "%s has no member %s" % (m.group(1), m.group(2)))

	typed = dict(TYPED_VARS)
	typed.update(service_vars)
	for m in re.finditer(r"(?<![\w.])(\w+)([.:])([A-Z]\w*)\b", text):
		var, sep, member = m.groups()
		cls = typed.get(var)
		if not cls:
			continue
		# skip table-field definitions like `function Foo.Bar` and module locals shadowing names
		before = text[max(0, m.start() - 9) : m.start()]
		if before.endswith("function "):
			continue
		if cls in DATATYPE_MEMBERS:
			if member not in DATATYPE_MEMBERS[cls]:
				report(m.start(), "%s (%s) has no member %s" % (var, cls, member))
			continue
		members = api.members(cls)
		if member not in members:
			# children found by name (e.g. root.RootAttachment / model.HumanoidRootPart) are fine
			if var in ("model", "character", "torso", "root", "arm", "head", "Workspace") and sep == ".":
				continue
			report(m.start(), "%s (%s) has no member %s" % (var, cls, member))
		else:
			mem = members[member]
			if "Deprecated" in (mem.get("Tags") or []) and member not in ("Font",):
				report(m.start(), "%s.%s is deprecated" % (cls, member))


def main():
	dump = load_dump(sys.argv[1] if len(sys.argv) > 1 else None)
	api = Api(dump)
	problems = []
	for dirpath, _, files in os.walk(SRC):
		for name in files:
			if name.endswith(".luau") or name.endswith(".lua"):
				check_file(api, os.path.join(dirpath, name), problems)
	for p in problems:
		print(p)
	print("%d problem(s)" % len(problems))
	sys.exit(1 if problems else 0)


if __name__ == "__main__":
	main()
