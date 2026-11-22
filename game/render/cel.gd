class_name Cel
extends RefCounted
## Swaps imported (glTF) or plain materials for the cel shader plus outline,
## keeping each surface's colour and texture.

const CEL := preload("res://game/render/cel.gdshader")
const OUTLINE := preload("res://game/render/outline.gdshader")

static var _cache := {}


static func material(color: Color, outline := true, thickness := 0.025, tex: Texture2D = null) -> ShaderMaterial:
	var key := "%s|%s|%s|%s" % [color.to_html(), outline, thickness, tex.resource_path if tex else ""]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = CEL
	m.set_shader_parameter("albedo", color)
	if tex:
		m.set_shader_parameter("albedo_tex", tex)
	if outline:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("thickness", thickness)
		m.next_pass = o
	_cache[key] = m
	return m


## A unique (uncached) copy, for things that animate parameters like fade.
static func unique_material(color: Color, outline := true, thickness := 0.025) -> ShaderMaterial:
	var m := material(color, outline, thickness).duplicate(true)
	return m


static func apply(root: Node, outline := true, thickness := 0.025) -> void:
	for mi in _meshes(root):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src: Material = mi.get_surface_override_material(i)
			if src == null:
				src = mesh.surface_get_material(i)
			var color := Color(0.8, 0.8, 0.8)
			var tex: Texture2D = null
			if src is BaseMaterial3D:
				color = (src as BaseMaterial3D).albedo_color
				tex = (src as BaseMaterial3D).albedo_texture
			elif src is ShaderMaterial and (src as ShaderMaterial).shader == CEL:
				continue
			mi.set_surface_override_material(i, material(color, outline, thickness, tex))


static func _meshes(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_meshes(c))
	return out
