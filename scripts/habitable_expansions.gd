class_name HabitableExpansions
extends RefCounted

# 將各區段擴建為「至少 5 個以上連通房間／子區段」的模組化建置器

const PROP_DIR := "res://assets/models/props/"
const MODEL_DIR := "res://assets/models/"
const WALL_T := 0.4


static func build_all(hz: Node3D, geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	_expand_gothic(hz, geo, lights, props)
	_expand_ouroboros(hz, geo, lights, props)
	_expand_garden(hz, geo, lights, props)
	_expand_paths(hz, geo, lights, props)
	_expand_lore(hz, geo, lights, props)


static func _expand_gothic(hz: Node3D, geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# 哥特段擴建（原主廳 x:-48..-24, z:2..20 為區段1）：
	# 區段2：西側拱柱長廊 (-62..-48, 8..14)
	# 區段3：阿麗亞娜生物研究室 (-72..-62, 2..20)
	# 區段4：南側隔離病房群 (-48..-32, 20..32)
	# 區段5：醫療物資庫房 (-32..-24, 20..30) ＋ 連通南側車道的環狀通道 (-24..-8, 23..27)
	var gh := 4.2
	var mat_white: Material = hz._mat_paint_white
	var mat_floor: Material = hz.MAT_HALL_FLOOR
	var mat_wall: Material = hz.MAT_HALL_WALL
	var mat_dark: Material = hz._mat_concrete_dark

	# 區段2：西側拱柱長廊
	hz._add_box(geo, Vector3(14.0, 0.2, 6.0), Vector3(-55.0, -0.1, 11.0), mat_floor, true)
	hz._add_box(geo, Vector3(14.0, 0.2, 6.0), Vector3(-55.0, gh + 0.1, 11.0), mat_white, true)
	hz._add_box(geo, Vector3(14.0, gh, WALL_T), Vector3(-55.0, gh * 0.5, 8.0), mat_white, true)
	hz._add_box(geo, Vector3(14.0, gh, WALL_T), Vector3(-55.0, gh * 0.5, 14.0), mat_white, true)
	hz._add_omni(lights, Vector3(-55.0, gh - 0.4, 11.0), Color(0.92, 0.96, 1.0), 1.0, 11.0, false, false)

	# 區段3：阿麗亞娜生物研究室 (-72..-62, 2..20)
	hz._add_box(geo, Vector3(10.0, 0.2, 18.0), Vector3(-67.0, -0.1, 11.0), mat_floor, true)
	hz._add_box(geo, Vector3(10.0, 0.2, 18.0), Vector3(-67.0, gh + 0.1, 11.0), mat_white, true)
	hz._add_box(geo, Vector3(WALL_T, gh, 18.0), Vector3(-72.0, gh * 0.5, 11.0), mat_white, true)
	hz._add_box(geo, Vector3(10.0, gh, WALL_T), Vector3(-67.0, gh * 0.5, 2.0), mat_white, true)
	hz._add_box(geo, Vector3(10.0, gh, WALL_T), Vector3(-67.0, gh * 0.5, 20.0), mat_white, true)
	hz._add_box(geo, Vector3(WALL_T, gh, 6.0), Vector3(-62.0, gh * 0.5, 5.0), mat_white, true)
	hz._add_box(geo, Vector3(WALL_T, gh, 6.0), Vector3(-62.0, gh * 0.5, 17.0), mat_white, true)
	hz._add_omni(lights, Vector3(-67.0, gh - 0.4, 11.0), Color(0.84, 0.98, 0.94), 1.25, 12.0, false, false)
	hz._spawn_model(props, MODEL_DIR + "retro_office_desk.glb", "GothicLabDesk", Vector3(-69.5, 0.0, 6.0), 90.0, Vector3(1.5, 0.78, 0.8))
	hz._spawn_model(props, PROP_DIR + "computer_screen.glb", "GothicLabScreen", Vector3(-69.5, 0.78, 6.0), 90.0, Vector3(0.5, 0.45, 0.4))
	hz._spawn_model(props, PROP_DIR + "fridge.glb", "GothicLabFridge", Vector3(-70.5, 0.0, 17.0), 90.0, Vector3(0.8, 1.7, 0.8))
	hz._add_note_prop(props, "GothicLabNote", Vector3(-69.5, 0.80, 5.5),
		"查看生物研究台上的樣本報告", "阿麗亞娜生物研究室",
		"【希波克拉底團隊 — 樣本分析室】\n\n"
		+ "研究主題：花園段（砼苑）植物孢子對人體組織的同化現象。\n"
		+ "結論：目前尚無逆轉藥劑，嚴禁任何人員進入花園段超過 45 分鐘。"
	)

	# 區段4：南側隔離病房群 (-48..-32, 20..32)
	hz._add_box(geo, Vector3(16.0, 0.2, 12.0), Vector3(-40.0, -0.1, 26.0), mat_floor, true)
	hz._add_box(geo, Vector3(16.0, 0.2, 12.0), Vector3(-40.0, gh + 0.1, 26.0), mat_white, true)
	hz._add_box(geo, Vector3(WALL_T, gh, 12.0), Vector3(-48.0, gh * 0.5, 26.0), mat_white, true)
	hz._add_box(geo, Vector3(16.0, gh, WALL_T), Vector3(-40.0, gh * 0.5, 32.0), mat_white, true)
	hz._add_box(geo, Vector3(0.22, 3.0, 8.0), Vector3(-40.0, 1.5, 28.0), mat_white, true) # 隔間牆分出兩間獨立病房
	hz._add_omni(lights, Vector3(-44.0, gh - 0.4, 26.0), Color(0.92, 0.96, 1.0), 1.0, 11.0, false, true)
	hz._add_omni(lights, Vector3(-36.0, gh - 0.4, 26.0), Color(0.92, 0.96, 1.0), 1.0, 11.0, false, false)
	hz._spawn_model(props, PROP_DIR + "armchair.glb", "IsoBed_1", Vector3(-44.5, 0.0, 29.5), 180.0, Vector3(1.6, 1.0, 1.5))
	hz._spawn_model(props, PROP_DIR + "armchair.glb", "IsoBed_2", Vector3(-36.5, 0.0, 29.5), 180.0, Vector3(1.6, 1.0, 1.5))

	# 區段5：醫療物資庫房 (-32..-24, 20..30) ＋ 連通南側車道 (x:-24..-8, z:23..27)
	hz._add_box(geo, Vector3(8.0, 0.2, 10.0), Vector3(-28.0, -0.1, 25.0), mat_floor, true)
	hz._add_box(geo, Vector3(8.0, 0.2, 10.0), Vector3(-28.0, gh + 0.1, 25.0), mat_white, true)
	hz._add_box(geo, Vector3(8.0, gh, WALL_T), Vector3(-28.0, gh * 0.5, 30.0), mat_white, true)
	hz._add_box(geo, Vector3(WALL_T, gh, 3.0), Vector3(-24.0, gh * 0.5, 21.5), mat_white, true)
	hz._add_box(geo, Vector3(WALL_T, gh, 3.0), Vector3(-24.0, gh * 0.5, 28.5), mat_white, true)
	hz._spawn_model(props, PROP_DIR + "shelf_small.glb", "MedStoreShelf", Vector3(-28.0, 0.0, 28.8), 180.0, Vector3(1.2, 1.8, 0.5))
	hz._spawn_model(props, PROP_DIR + "box_closed.glb", "MedStoreBox", Vector3(-26.0, 0.0, 21.5), 15.0, Vector3(0.7, 0.7, 0.7))

	# 環狀連通走廊接回南側積水車道西牆 (x:-24..-8, z:23..27)
	hz._add_box(geo, Vector3(16.0, 0.2, 4.0), Vector3(-16.0, -0.1, 25.0), mat_floor, true)
	hz._add_box(geo, Vector3(16.0, 0.2, 4.0), Vector3(-16.0, 3.7, 25.0), mat_dark, true)
	hz._add_box(geo, Vector3(16.0, 3.6, WALL_T), Vector3(-16.0, 1.8, 23.0), mat_wall, true)
	hz._add_box(geo, Vector3(16.0, 3.6, WALL_T), Vector3(-16.0, 1.8, 27.0), mat_wall, true)
	hz._add_omni(lights, Vector3(-16.0, 3.2, 25.0), Color(0.84, 0.90, 0.96), 0.9, 10.0, false, false)


static func _expand_ouroboros(hz: Node3D, geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# 銜尾段擴建（原工地 x:10..28, z:-38..-20 為區段1）：
	# 區段2：北側未完工長廊 (16..22, -52..-38)
	# 區段3：西北水泥攪拌／材料間 (8..16, -54..-40)
	# 區段4：東北鷹架塔井 (22..36, -54..-38)
	# 區段5：最北側循環施工死胡同 (12..30, -64..-54)
	var oh := 4.2
	var mat_floor: Material = hz.MAT_HALL_FLOOR
	var mat_wall: Material = hz.MAT_HALL_WALL
	var mat_dark: Material = hz._mat_concrete_dark
	var mat_pipe: Material = hz._mat_pipe

	# 區段2：北側未完工長廊
	hz._add_box(geo, Vector3(6.0, 0.2, 16.0), Vector3(19.0, -0.1, -46.0), mat_floor, true)
	hz._add_box(geo, Vector3(6.0, 0.2, 16.0), Vector3(19.0, oh + 0.1, -46.0), mat_dark, true)
	hz._add_box(geo, Vector3(WALL_T, oh, 6.0), Vector3(16.0, oh * 0.5, -51.0), mat_wall, true)
	hz._add_box(geo, Vector3(WALL_T, oh, 6.0), Vector3(22.0, oh * 0.5, -51.0), mat_wall, true)
	hz._add_omni(lights, Vector3(19.0, 3.4, -46.0), Color(1.0, 0.78, 0.42), 1.0, 11.0, false, false)

	# 區段3：西北水泥材料間 (8..16, -54..-40)
	hz._add_box(geo, Vector3(8.0, 0.2, 14.0), Vector3(12.0, -0.1, -47.0), mat_floor, true)
	hz._add_box(geo, Vector3(8.0, 0.2, 14.0), Vector3(12.0, oh + 0.1, -47.0), mat_dark, true)
	hz._add_box(geo, Vector3(WALL_T, oh, 14.0), Vector3(8.0, oh * 0.5, -47.0), mat_wall, true)
	hz._add_box(geo, Vector3(8.0, oh, WALL_T), Vector3(12.0, oh * 0.5, -40.0), mat_wall, true)
	hz._add_box(geo, Vector3(8.0, oh, WALL_T), Vector3(12.0, oh * 0.5, -54.0), mat_wall, true)
	hz._spawn_model(props, PROP_DIR + "pallet.glb", "OuroMatPallet", Vector3(10.5, 0.0, -45.0), 0.0, Vector3(1.2, 0.18, 1.0))
	hz._spawn_model(props, PROP_DIR + "barrel.glb", "OuroMatBarrel", Vector3(10.5, 0.0, -49.0), 0.0, Vector3(0.6, 0.9, 0.6))
	hz._spawn_model(props, PROP_DIR + "ladder.glb", "OuroMatLadder", Vector3(9.0, 0.0, -52.0), 90.0, Vector3(0.6, 2.2, 0.4))

	# 區段4：東北鷹架塔井 (22..36, -54..-38)
	hz._add_box(geo, Vector3(14.0, 0.2, 16.0), Vector3(29.0, -0.1, -46.0), mat_floor, true)
	hz._add_box(geo, Vector3(14.0, 0.2, 16.0), Vector3(29.0, 5.8, -46.0), mat_dark, true)
	hz._add_box(geo, Vector3(WALL_T, 5.8, 16.0), Vector3(36.0, 2.9, -46.0), mat_wall, true)
	hz._add_box(geo, Vector3(14.0, 5.8, WALL_T), Vector3(29.0, 2.9, -38.0), mat_wall, true)
	hz._add_box(geo, Vector3(14.0, 5.8, WALL_T), Vector3(29.0, 2.9, -54.0), mat_wall, true)
	hz._add_box(geo, Vector3(10.0, 0.16, 2.2), Vector3(29.0, 2.2, -46.0), mat_pipe, true)
	hz._add_omni(lights, Vector3(29.0, 4.6, -46.0), Color(1.0, 0.72, 0.36), 1.2, 13.0, false, true)

	# 區段5：最北側循環施工死胡同 (12..30, -64..-54)
	hz._add_box(geo, Vector3(18.0, 0.2, 10.0), Vector3(21.0, -0.1, -59.0), mat_floor, true)
	hz._add_box(geo, Vector3(18.0, 0.2, 10.0), Vector3(21.0, oh + 0.1, -59.0), mat_dark, true)
	hz._add_box(geo, Vector3(WALL_T, oh, 10.0), Vector3(12.0, oh * 0.5, -59.0), mat_wall, true)
	hz._add_box(geo, Vector3(WALL_T, oh, 10.0), Vector3(30.0, oh * 0.5, -59.0), mat_wall, true)
	hz._add_box(geo, Vector3(18.0, oh, WALL_T), Vector3(21.0, oh * 0.5, -64.0), mat_wall, true)
	hz._add_box(geo, Vector3(4.0, 2.6, 0.4), Vector3(21.0, 1.3, -63.6), hz.MAT_DARK_BRICK, true)
	hz._add_note_prop(props, "OuroDeadEndNote", Vector3(21.0, 0.05, -61.5),
		"撿起砌死磚門前的工頭夾板", "銜尾段工頭紀錄",
		"「這是第 412 次把這扇門砌起來，明天大概又會自己裂開。」"
	)


static func _expand_garden(hz: Node3D, geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# 花園段／砼苑擴建（原中央水池大廳 x:46..70, z:-64..-44 為區段1）：
	# 區段2：北側藤蔓溫室長廊 (54..62, -76..-64)
	# 區段3：西北苔蘚花房 (42..54, -84..-66)
	# 區段4：東北枯樹樹根廳 (62..82, -84..-64)
	# 區段5：東側被植物吞沒的車庫殘骸 (70..92, -60..-44)
	var by := -4.0
	var gh := 5.5
	var mat_moss := StandardMaterial3D.new()
	mat_moss.albedo_color = Color(0.14, 0.32, 0.16)
	mat_moss.roughness = 0.95
	var mat_vine := StandardMaterial3D.new()
	mat_vine.albedo_color = Color(0.18, 0.46, 0.20)
	mat_vine.roughness = 0.88

	# 區段2：北側藤蔓溫室長廊 (54..62, -76..-64)
	hz._add_box(geo, Vector3(8.0, 0.2, 12.0), Vector3(58.0, by - 0.1, -70.0), mat_moss, true)
	hz._add_box(geo, Vector3(8.0, 0.2, 12.0), Vector3(58.0, by + gh + 0.1, -70.0), hz._mat_concrete_dark, true)
	hz._add_box(geo, Vector3(8.0, gh, WALL_T), Vector3(58.0, by + gh * 0.5, -76.0), hz.MAT_HALL_WALL, true)
	hz._add_omni(lights, Vector3(58.0, by + gh - 0.5, -70.0), Color(0.65, 0.94, 0.55), 1.3, 13.0, false, false)

	# 區段3：西北苔蘚花房 (42..54, -84..-66)
	hz._add_box(geo, Vector3(12.0, 0.2, 18.0), Vector3(48.0, by - 0.1, -75.0), mat_moss, true)
	hz._add_box(geo, Vector3(12.0, 0.2, 18.0), Vector3(48.0, by + 4.0, -75.0), hz._mat_concrete_dark, true)
	hz._add_box(geo, Vector3(WALL_T, 4.0, 18.0), Vector3(42.0, by + 2.0, -75.0), hz.MAT_HALL_WALL, true)
	hz._add_box(geo, Vector3(12.0, 4.0, WALL_T), Vector3(48.0, by + 2.0, -84.0), hz.MAT_HALL_WALL, true)
	hz._add_box(geo, Vector3(12.0, 4.0, WALL_T), Vector3(48.0, by + 2.0, -66.0), hz.MAT_HALL_WALL, true)
	hz._add_omni(lights, Vector3(48.0, by + 3.4, -75.0), Color(0.42, 0.88, 0.48), 1.1, 11.0, false, false)
	hz._spawn_model(props, PROP_DIR + "plant.glb", "GardenNWPlant_1", Vector3(45.0, by, -80.0), 15.0, Vector3(0.6, 1.0, 0.6))
	hz._spawn_model(props, PROP_DIR + "plant.glb", "GardenNWPlant_2", Vector3(50.0, by, -72.0), 45.0, Vector3(0.6, 1.0, 0.6))

	# 區段4：東北樹根廳 (62..82, -84..-64)
	hz._add_box(geo, Vector3(20.0, 0.2, 20.0), Vector3(72.0, by - 0.1, -74.0), mat_moss, true)
	hz._add_box(geo, Vector3(20.0, 0.2, 20.0), Vector3(72.0, by + gh + 0.1, -74.0), hz._mat_concrete_dark, true)
	hz._add_box(geo, Vector3(WALL_T, gh, 20.0), Vector3(82.0, by + gh * 0.5, -74.0), hz.MAT_HALL_WALL, true)
	hz._add_box(geo, Vector3(20.0, gh, WALL_T), Vector3(72.0, by + gh * 0.5, -84.0), hz.MAT_HALL_WALL, true)
	hz._add_box(geo, Vector3(20.0, gh, WALL_T), Vector3(72.0, by + gh * 0.5, -64.0), hz.MAT_HALL_WALL, true)
	hz._add_box(geo, Vector3(2.2, gh, 2.2), Vector3(72.0, by + gh * 0.5, -74.0), mat_vine, true) # 巨型植物樹柱
	hz._add_omni(lights, Vector3(72.0, by + gh - 0.4, -74.0), Color(0.92, 0.96, 0.68), 1.6, 15.0, false, false)

	# 區段5：東側被植物吞沒的車庫殘骸 (70..92, -60..-44)
	hz._add_box(geo, Vector3(22.0, 0.2, 16.0), Vector3(81.0, by - 0.1, -52.0), mat_moss, true)
	hz._add_box(geo, Vector3(22.0, 0.2, 16.0), Vector3(81.0, by + gh + 0.1, -52.0), hz._mat_concrete_dark, true)
	hz._add_box(geo, Vector3(WALL_T, gh, 16.0), Vector3(92.0, by + gh * 0.5, -52.0), hz.MAT_HALL_WALL, true)
	hz._add_box(geo, Vector3(22.0, gh, WALL_T), Vector3(81.0, by + gh * 0.5, -60.0), hz.MAT_HALL_WALL, true)
	hz._add_box(geo, Vector3(22.0, gh, WALL_T), Vector3(81.0, by + gh * 0.5, -44.0), hz.MAT_HALL_WALL, true)
	hz._spawn_model(props, PROP_DIR + "car_sedan.glb", "GardenWreckCar", Vector3(83.0, by, -52.0), -35.0, Vector3(2.1, 1.5, 4.3))
	hz._add_box(geo, Vector3(2.6, 0.8, 2.0), Vector3(83.0, by + 0.4, -52.0), mat_vine, false)
	hz._add_omni(lights, Vector3(81.0, by + gh - 0.5, -52.0), Color(0.55, 0.92, 0.58), 1.25, 13.0, false, false)


static func _expand_paths(hz: Node3D, geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# 小徑擴建（原走廊＋北房＋南房 x:-32..-10 為區段1~3）：
	# 區段4：西延白水泥走廊 (-48..-32, -29..-25)
	# 區段5：西端家具雜物房 (-48..-36, -35..-29)
	# 區段6：最西端閃爍暗房 (-56..-48, -32..-22)
	var mat_white: Material = hz._mat_paint_white
	hz._add_box(geo, Vector3(16.0, 0.2, 4.0), Vector3(-40.0, -0.1, -27.0), hz.MAT_HALL_FLOOR, true)
	hz._add_box(geo, Vector3(16.0, 0.2, 4.0), Vector3(-40.0, 2.9, -27.0), mat_white, true)
	hz._add_box(geo, Vector3(16.0, 2.8, WALL_T), Vector3(-40.0, 1.4, -25.0), mat_white, true)
	hz._add_box(geo, Vector3(8.0, 2.8, WALL_T), Vector3(-36.0, 1.4, -29.0), mat_white, true)
	hz._add_box(geo, Vector3(4.0, 2.8, WALL_T), Vector3(-46.0, 1.4, -29.0), mat_white, true) # x:-44..-40 留門洞

	# 區段5：西端家具雜物房 (-48..-36, -35..-29)
	hz._add_box(geo, Vector3(12.0, 0.2, 6.0), Vector3(-42.0, -0.1, -32.0), hz.MAT_HALL_FLOOR, true)
	hz._add_box(geo, Vector3(12.0, 0.2, 6.0), Vector3(-42.0, 2.9, -32.0), mat_white, true)
	hz._add_box(geo, Vector3(WALL_T, 2.8, 6.0), Vector3(-36.0, 1.4, -32.0), mat_white, true)
	hz._add_box(geo, Vector3(WALL_T, 2.8, 6.0), Vector3(-48.0, 1.4, -32.0), mat_white, true)
	hz._add_box(geo, Vector3(12.0, 2.8, WALL_T), Vector3(-42.0, 1.4, -35.0), mat_white, true)
	hz._add_omni(lights, Vector3(-42.0, 2.4, -32.0), Color(0.88, 0.92, 0.96), 0.85, 9.0, false, false)
	hz._spawn_model(props, PROP_DIR + "shelf_small.glb", "PathsWestShelf", Vector3(-46.5, 0.0, -32.0), 90.0, Vector3(1.2, 1.8, 0.5))

	# 區段6：最西端閃爍暗房 (-56..-48, -32..-22)
	hz._add_box(geo, Vector3(8.0, 0.2, 10.0), Vector3(-52.0, -0.1, -27.0), hz.MAT_HALL_FLOOR, true)
	hz._add_box(geo, Vector3(8.0, 0.2, 10.0), Vector3(-52.0, 2.9, -27.0), mat_white, true)
	hz._add_box(geo, Vector3(WALL_T, 2.8, 10.0), Vector3(-56.0, 1.4, -27.0), mat_white, true)
	hz._add_box(geo, Vector3(8.0, 2.8, WALL_T), Vector3(-52.0, 1.4, -32.0), mat_white, true)
	hz._add_box(geo, Vector3(8.0, 2.8, WALL_T), Vector3(-52.0, 1.4, -22.0), mat_white, true)
	hz._add_omni(lights, Vector3(-52.0, 2.4, -27.0), Color(0.75, 0.84, 0.92), 0.55, 8.0, false, true)
	hz._spawn_model(props, PROP_DIR + "cardboard_boxes.glb", "PathsEndBox", Vector3(-54.5, 0.0, -27.0), 15.0, Vector3(0.9, 0.8, 0.9))


static func _expand_lore(hz: Node3D, geo: StaticBody3D, lights: Node3D, props: Node3D) -> void:
	# 傳說段擴建（原正廳＋古代書房＋霓虹長廊為區段1~3）：
	# 區段4：古老藏經／檔案閣 (96..108, 26..36, y=-4.0)
	# 區段5：霓虹電纜總匯機房 (80..96, 38..48, y=-4.0)
	var by := -4.0
	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.32, 0.11, 0.10)
	mat_wood.roughness = 0.82

	# 區段4：古老藏經／檔案閣 (96..108, 26..36)
	hz._add_box(geo, Vector3(12.0, 0.2, 10.0), Vector3(102.0, by - 0.1, 31.0), mat_wood, true)
	hz._add_box(geo, Vector3(12.0, 0.2, 10.0), Vector3(102.0, by + 3.6, 31.0), mat_wood, true)
	hz._add_box(geo, Vector3(WALL_T, 3.6, 10.0), Vector3(96.0, by + 1.8, 31.0), mat_wood, true)
	hz._add_box(geo, Vector3(WALL_T, 3.6, 10.0), Vector3(108.0, by + 1.8, 31.0), mat_wood, true)
	hz._add_box(geo, Vector3(12.0, 3.6, WALL_T), Vector3(102.0, by + 1.8, 36.0), mat_wood, true)
	hz._add_omni(lights, Vector3(102.0, by + 3.0, 31.0), Color(1.0, 0.78, 0.45), 1.15, 11.0, false, false)
	hz._spawn_model(props, PROP_DIR + "shelf_small.glb", "LoreArchShelf_1", Vector3(105.0, by, 28.0), -90.0, Vector3(1.2, 1.8, 0.5))
	hz._spawn_model(props, PROP_DIR + "shelf_small.glb", "LoreArchShelf_2", Vector3(105.0, by, 33.0), -90.0, Vector3(1.2, 1.8, 0.5))

	# 區段5：霓虹電纜總匯機房 (80..96, 38..48)
	hz._add_box(geo, Vector3(16.0, 0.2, 10.0), Vector3(88.0, by - 0.1, 43.0), hz._mat_concrete_dark, true)
	hz._add_box(geo, Vector3(16.0, 0.2, 10.0), Vector3(88.0, by + 3.8, 43.0), hz._mat_concrete_dark, true)
	hz._add_box(geo, Vector3(WALL_T, 3.8, 10.0), Vector3(80.0, by + 1.9, 43.0), mat_wood, true)
	hz._add_box(geo, Vector3(WALL_T, 3.8, 10.0), Vector3(96.0, by + 1.9, 43.0), mat_wood, true)
	hz._add_box(geo, Vector3(16.0, 3.8, WALL_T), Vector3(88.0, by + 1.9, 48.0), hz._mat_concrete_dark, true)
	hz._add_omni(lights, Vector3(88.0, by + 3.1, 43.0), Color(0.25, 0.90, 1.0), 1.35, 12.0, false, true)
	hz._spawn_model(props, MODEL_DIR + "breaker_box.glb", "LoreCableBreaker", Vector3(95.4, by + 1.4, 43.0), -90.0, Vector3(0.35, 0.7, 0.5))
