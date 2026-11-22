class_name CityBlock
extends RefCounted
## Builds a generated block (BlockGenerator) into a DestructionWorld, so
## every wall, floor, window and lamp post can be shot and broken, and
## registers each building with the roof fader.


## Returns the generator, for spawn points and building bounds.
static func build(world: DestructionWorld, seed_value: int, fader: RoofFader = null) -> BlockGenerator:
	var g := BlockGenerator.generate(seed_value)
	var ids: Array = []
	for p in g.pieces:
		var held: int = ids[p.held_by] if p.held_by >= 0 else -1
		ids.append(world.add_piece(p.kind, p.xform, p.bears, p.tint, held))
	world.finalize()
	if fader:
		for b in g.buildings:
			fader.add_building_from_world(world, b.bounds)
	return g
