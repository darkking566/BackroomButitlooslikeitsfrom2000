class_name HabitableStructures
extends RefCounted

# 為「宜居地帶」每個區域增加大量結構細節、建築小品與物件

const PROP_DIR := "res://assets/models/props/"
const MODEL_DIR := "res://assets/models/"


static func populate_all(hz: Node3D, geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	_populate_aquila_garage(hz, geo, lights, props)
	_populate_gothic(hz, geo, lights, props)
	_populate_ouroboros(hz, geo, lights, props)
	_populate_garden(hz, geo, lights, props)
	_populate_paths(hz, geo, lights, props)
	_populate_lore(hz, geo, lights, props)
	_populate_b2_extras(hz, geo, lights, props)


static func _populate_aquila_garage(hz: Node3D, geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# 1. B1 停車場管理亭／收費亭 (x: -7.5..-3.5, z: -15..-11)
	var mat_dark: Material = hz._mat_concrete_dark
	var mat_wall: Material = hz.MAT_HALL_WALL
	var mat_glass := StandardMaterial3D.new()
	mat_glass.albedo_color = Color(0.55, 0.68, 0.70, 0.55)
	mat_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_glass.roughness = 0.2

	hz._add_box(geo, Vector3(4.0, 1.05, 4.0), Vector3(-5.5, 0.525, -13.0), mat_wall, true)
	hz._add_box(geo, Vector3(4.2, 0.2, 4.2), Vector3(-5.5, 2.7, -13.0), mat_dark, true)
	for cx in [-7.35, -3.65]:
		for cz in [-14.85, -11.15]:
			hz._add_box(geo, Vector3(0.18, 1.6, 0.18), Vector3(cx, 1.85, cz), mat_dark, false)
	hz._add_box(geo, Vector3(3.6, 1.3, 0.08), Vector3(-5.5, 1.85, -11.15), mat_glass, false)
	hz._add_box(geo, Vector3(0.08, 1.3, 3.6), Vector3(-3.65, 1.85, -13.0), mat_glass, false)
	hz._add_omni(lights, Vector3(-5.5, 2.4, -13.0), Color(0.85, 0.96, 0.85), 0.95, 8.0, false, false)
	hz._spawn_model(props, PROP_DIR + "computer_screen.glb", "BoothScreen", Vector3(-5.5, 1.05, -13.0), 0.0, Vector3(0.45, 0.45, 0.4))

	# 2. 更多停放車輛與水泥防撞車擋 (Wheel Stops)
	hz._spawn_model(props, PROP_DIR + "car_sedan.glb", "CarSedan_2", Vector3(-12.5, 0.0, -13.2), 182.0, Vector3(2.1, 1.5, 4.3))
	hz._spawn_model(props, PROP_DIR + "car_suv.glb", "CarSUV_2", Vector3(12.5, 0.0, 13.2), 92.0, Vector3(4.5, 1.65, 2.25))
	for pz in [-13.2, -9.8, 9.8, 13.2]:
		hz._add_box(geo, Vector3(0.22, 0.14, 1.9), Vector3(-14.8, 0.07, pz), hz._mat_hazard, true)
		hz._add_box(geo, Vector3(0.22, 0.14, 1.9), Vector3(14.8, 0.07, pz), hz._mat_hazard, true)

	# 3. 卸貨區雜物堆（棧板、鐵桶、垃圾桶、三角錐、文件櫃）
	hz._spawn_model(props, PROP_DIR + "pallet.glb", "GaragePallet_2", Vector3(6.5, 0.0, 14.5), 25.0, Vector3(1.2, 0.18, 1.0))
	hz._spawn_model(props, PROP_DIR + "barrel.glb", "GarageBarrel_3", Vector3(6.2, 0.18, 14.5), 0.0, Vector3(0.6, 0.9, 0.6))
	hz._spawn_model(props, PROP_DIR + "cardboard_boxes.glb", "GarageBoxes_2", Vector3(8.0, 0.0, 15.2), -15.0, Vector3(0.9, 0.8, 0.9))
	hz._spawn_model(props, PROP_DIR + "trashcan.glb", "GarageTrash_1", Vector3(-19.0, 0.0, 4.0), 0.0, Vector3(0.5, 0.8, 0.5))
	hz._spawn_model(props, PROP_DIR + "traffic_cone.glb", "GarageCone_4", Vector3(-8.5, 0.0, -7.5), 0.0, Vector3(0.55, 0.72, 0.55))
	hz._spawn_model(props, MODEL_DIR + "filing_cabinet.glb", "GarageCab_1", Vector3(18.5, 0.0, -18.5), 0.0, Vector3(0.6, 1.4, 0.7))


static func _populate_gothic(hz: Node3D, geo: StaticBody3D, _lights: Node3D, props: Node3D) -> void:
	var mat_white: Material = hz._mat_paint_white
	var mat_glow := StandardMaterial3D.new()
	mat_glow.albedo_color = Color(0.35, 0.95, 0.80)
	mat_glow.emission_enabled = true
	mat_glow.emission = Color(0.25, 0.85, 0.72)
	mat_glow.emission_energy_multiplier = 1.6

	# 1. 西側拱柱長廊加上對稱小圓柱
	for cx in [-52.0, -56.0, -60.0]:
		for cz in [8.8, 13.2]:
			hz._add_box(geo, Vector3(0.45, 4.2, 0.45), Vector3(cx, 2.1, cz), mat_white, true)
			hz._add_box(geo, Vector3(0.85, 0.35, 0.85), Vector3(cx, 4.0, cz), mat_white, false)

	# 2. 生物研究室：發光培養槽與多組實驗櫃
	for bz in [9.5, 12.5]:
		hz._add_box(geo, Vector3(0.8, 0.9, 0.8), Vector3(-68.0, 0.45, bz), hz._mat_concrete_dark, true)
		hz._add_box(geo, Vector3(0.6, 1.3, 0.6), Vector3(-68.0, 1.55, bz), mat_glow, true)
	hz._spawn_model(props, MODEL_DIR + "filing_cabinet.glb", "GothicLabCab_1", Vector3(-70.8, 0.0, 3.2), 90.0, Vector3(0.6, 1.4, 0.7))
	hz._spawn_model(props, MODEL_DIR + "filing_cabinet.glb", "GothicLabCab_2", Vector3(-70.8, 0.0, 4.0), 90.0, Vector3(0.6, 1.4, 0.7))
	hz._spawn_model(props, MODEL_DIR + "office_chair.glb", "GothicLabChair", Vector3(-68.5, 0.0, 6.0), -80.0, Vector3(0.65, 0.95, 0.65))

	# 3. 隔離病房與醫療庫房物件
	hz._spawn_model(props, PROP_DIR + "trashcan.glb", "GothicTrash", Vector3(-42.0, 0.0, 22.0), 0.0, Vector3(0.5, 0.8, 0.5))
	hz._spawn_model(props, PROP_DIR + "bucket.glb", "GothicBucket", Vector3(-34.0, 0.0, 22.0), 0.0, Vector3(0.4, 0.5, 0.4))
	hz._spawn_model(props, PROP_DIR + "barrel.glb", "MedStoreBarrel", Vector3(-30.5, 0.0, 28.5), 0.0, Vector3(0.6, 0.9, 0.6))
	hz._spawn_model(props, PROP_DIR + "cardboard_boxes.glb", "MedStoreBoxes", Vector3(-25.5, 0.0, 28.5), 25.0, Vector3(0.9, 0.8, 0.9))


static func _populate_ouroboros(hz: Node3D, geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# 鷹架塔井加上雙層平台、斜坡木板、垂直鋼管與更多工地雜物
	var mat_pipe: Material = hz._mat_pipe
	var mat_dark: Material = hz._mat_concrete_dark
	for sx in [25.5, 32.5]:
		for sz in [-49.5, -42.5]:
			hz._add_box(geo, Vector3(0.18, 5.6, 0.18), Vector3(sx, 2.8, sz), mat_pipe, false)
	hz._add_box(geo, Vector3(7.2, 0.16, 7.2), Vector3(29.0, 4.0, -46.0), mat_dark, false)
	hz._add_rotated_box(geo, Vector3(5.5, 0.16, 1.4), Vector3(26.5, 1.1, -46.0), Vector3(0.0, 0.0, 0.42), hz._mat_hazard, true)

	hz._spawn_model(props, PROP_DIR + "pallet.glb", "OuroTowerPallet", Vector3(33.5, 0.0, -41.0), 15.0, Vector3(1.2, 0.18, 1.0))
	hz._spawn_model(props, PROP_DIR + "cardboard_boxes.glb", "OuroTowerBoxes", Vector3(33.5, 0.18, -41.0), 0.0, Vector3(0.9, 0.8, 0.9))
	hz._spawn_model(props, PROP_DIR + "traffic_cone.glb", "OuroNorthCone_1", Vector3(17.5, 0.0, -42.0), 0.0, Vector3(0.55, 0.72, 0.55))
	hz._spawn_model(props, PROP_DIR + "traffic_cone.glb", "OuroNorthCone_2", Vector3(20.5, 0.0, -42.0), 0.0, Vector3(0.55, 0.72, 0.55))
	hz._spawn_model(props, PROP_DIR + "barrel.glb", "OuroDeadEndBarrel", Vector3(14.0, 0.0, -61.5), 0.0, Vector3(0.6, 0.9, 0.6))
	hz._add_omni(lights, Vector3(12.0, 2.8, -47.0), Color(1.0, 0.76, 0.40), 0.9, 10.0, false, false)


static func _populate_garden(hz: Node3D, geo: StaticBody3D, _lights: Node3D, props: Node3D) -> void:
	var by := -4.0
	var mat_vine := StandardMaterial3D.new()
	mat_vine.albedo_color = Color(0.18, 0.46, 0.20)
	mat_vine.roughness = 0.88

	# 1. 北側溫室長廊：鐵管拱架
	for gz in [-66.5, -70.0, -73.5]:
		hz._add_box(geo, Vector3(0.16, 4.8, 0.16), Vector3(54.4, by + 2.4, gz), hz._mat_pipe, false)
		hz._add_box(geo, Vector3(0.16, 4.8, 0.16), Vector3(61.6, by + 2.4, gz), hz._mat_pipe, false)
		hz._add_box(geo, Vector3(7.4, 0.16, 0.16), Vector3(58.0, by + 4.8, gz), hz._mat_pipe, false)

	# 2. 東北樹根廳：從中央巨樹柱往外延伸的四條巨型斜向樹根
	hz._add_rotated_box(geo, Vector3(6.5, 0.55, 0.7), Vector3(69.0, by + 0.9, -74.0), Vector3(0.0, 0.0, 0.35), mat_vine, true)
	hz._add_rotated_box(geo, Vector3(6.5, 0.55, 0.7), Vector3(75.0, by + 0.9, -74.0), Vector3(0.0, 0.0, -0.35), mat_vine, true)
	hz._add_rotated_box(geo, Vector3(0.7, 0.55, 6.5), Vector3(72.0, by + 0.9, -71.0), Vector3(-0.35, 0.0, 0.0), mat_vine, true)
	hz._add_rotated_box(geo, Vector3(0.7, 0.55, 6.5), Vector3(72.0, by + 0.9, -77.0), Vector3(0.35, 0.0, 0.0), mat_vine, true)
	hz._spawn_model(props, PROP_DIR + "plant.glb", "GardenRootPlant_1", Vector3(66.0, by, -68.0), 10.0, Vector3(0.7, 1.1, 0.7))
	hz._spawn_model(props, PROP_DIR + "plant.glb", "GardenRootPlant_2", Vector3(78.0, by, -80.0), 45.0, Vector3(0.7, 1.1, 0.7))

	# 3. 植物車庫殘骸：再加幾盆植物與鐵桶
	hz._spawn_model(props, PROP_DIR + "barrel.glb", "GardenWreckBarrel", Vector3(88.0, by, -47.0), 0.0, Vector3(0.6, 0.9, 0.6))
	hz._spawn_model(props, PROP_DIR + "plant.glb", "GardenWreckPlant", Vector3(80.0, by, -57.0), 0.0, Vector3(0.6, 1.0, 0.6))


static func _populate_paths(hz: Node3D, geo: StaticBody3D, _lights: Node3D, props: Node3D) -> void:
	# 小徑西延區補齊門框、舊家具、冰箱、落地燈與垃圾桶
	for fx in [-35.0, -42.0, -47.5]:
		hz._add_box(geo, Vector3(0.18, 2.4, 0.25), Vector3(fx, 1.2, -28.8), hz._mat_concrete_dark, false)
	hz._spawn_model(props, PROP_DIR + "armchair.glb", "PathsWestCouch", Vector3(-39.0, 0.0, -33.2), 0.0, Vector3(1.6, 1.0, 1.5))
	hz._spawn_model(props, PROP_DIR + "fridge.glb", "PathsWestFridge", Vector3(-37.2, 0.0, -30.5), -90.0, Vector3(0.8, 1.7, 0.8))
	hz._spawn_model(props, PROP_DIR + "floor_lamp.glb", "PathsWestLamp", Vector3(-46.5, 0.0, -33.8), 0.0, Vector3(0.4, 1.6, 0.4))
	hz._spawn_model(props, PROP_DIR + "trashcan.glb", "PathsEndTrash", Vector3(-54.5, 0.0, -23.5), 0.0, Vector3(0.5, 0.8, 0.5))
	hz._spawn_model(props, PROP_DIR + "pallet_broken.glb", "PathsEndPallet", Vector3(-52.0, 0.0, -30.5), 20.0, Vector3(1.2, 0.18, 1.0))


static func _populate_lore(hz: Node3D, geo: StaticBody3D, _lights: Node3D, props: Node3D) -> void:
	var by := -4.0
	# 1. 檔案閣：多排書架、檔案櫃、書桌與落地燈
	hz._spawn_model(props, MODEL_DIR + "filing_cabinet.glb", "LoreArchCab_1", Vector3(97.5, by, 34.0), 90.0, Vector3(0.6, 1.4, 0.7))
	hz._spawn_model(props, MODEL_DIR + "filing_cabinet.glb", "LoreArchCab_2", Vector3(97.5, by, 34.8), 90.0, Vector3(0.6, 1.4, 0.7))
	hz._spawn_model(props, PROP_DIR + "floor_lamp.glb", "LoreArchLamp", Vector3(106.5, by, 34.5), 0.0, Vector3(0.4, 1.6, 0.4))
	hz._spawn_model(props, PROP_DIR + "plant.glb", "LoreArchPlant", Vector3(106.5, by, 27.5), 0.0, Vector3(0.5, 0.9, 0.5))

	# 2. 霓虹機房：兩排大型發光伺服器機櫃
	var mat_led := StandardMaterial3D.new()
	mat_led.albedo_color = Color(0.2, 0.95, 1.0)
	mat_led.emission_enabled = true
	mat_led.emission = Color(0.2, 0.95, 1.0)
	mat_led.emission_energy_multiplier = 2.0
	for sx in [82.5, 86.0, 89.5, 93.0]:
		hz._add_box(geo, Vector3(1.1, 2.4, 1.1), Vector3(sx, by + 1.2, 46.2), hz._mat_concrete_dark, true)
		hz._add_box(geo, Vector3(0.85, 0.12, 0.08), Vector3(sx, by + 1.9, 45.62), mat_led, false)
	hz._spawn_model(props, MODEL_DIR + "retro_office_desk.glb", "LoreServerDesk", Vector3(83.0, by, 41.0), 90.0, Vector3(1.5, 0.78, 0.8))
	hz._spawn_model(props, PROP_DIR + "computer_screen.glb", "LoreServerScreen", Vector3(83.0, by + 0.78, 41.0), 90.0, Vector3(0.5, 0.45, 0.4))


static func _populate_b2_extras(hz: Node3D, geo: StaticBody3D, _lights: Node3D, props: Node3D) -> void:
	var by := -4.0
	# 貨櫃區補木箱／梯子；發電機房補控制儀表台
	hz._spawn_model(props, PROP_DIR + "ladder.glb", "ContLadder", Vector3(45.0, by, -31.5), 90.0, Vector3(0.6, 2.2, 0.4))
	hz._spawn_model(props, PROP_DIR + "cardboard_boxes.glb", "ContBoxes", Vector3(64.5, by, -32.0), 15.0, Vector3(0.9, 0.8, 0.9))
	hz._spawn_model(props, MODEL_DIR + "retro_office_desk.glb", "GenControlDesk", Vector3(79.5, by, 0.0), 90.0, Vector3(1.5, 0.78, 0.8))
	hz._spawn_model(props, PROP_DIR + "computer_screen.glb", "GenControlScreen", Vector3(79.5, by + 0.78, 0.0), 90.0, Vector3(0.5, 0.45, 0.4))
	hz._add_box(geo, Vector3(0.4, 1.4, 0.4), Vector3(88.5, by + 0.7, -3.5), hz._mat_hazard, true)
	hz._add_box(geo, Vector3(0.4, 1.4, 0.4), Vector3(88.5, by + 0.7, 3.5), hz._mat_hazard, true)
