# 貝克潤PS2 — Blender → PS2 → Godot 層級製作實戰筆記

本文件整理自「宜居地帶／天鷹段」實際從參考照片建模、壓縮為低面數 128px PS2 資產，並導入 Godot 除錯驗證的經驗，供後續製作其他層級與區段時直接參考與複用。

---

## 一、標準作業流程（SOP）

1. **對照原文圖抓出「識別核心」**
   - 先列出該區段最具辨識度的 4～6 個視覺元素（例如天鷹段的：左側上坡車道、帶柱帽與 `F` 字樣的方柱、右側鐵皮浪板＋垂掛電線、頭頂白管紅閥門、濕滑積水與兩條輪胎印）。
2. **Blender 試作與畫面構圖確認**
   - 先在 Blender 用乾淨場景把結構與光影關係試出來，用相機從玩家出生點高度（`z ≈ 1.48～1.55 m`）檢查構圖。
3. **轉製成低面數 PS2 資產（`.glb` + 128px PNG）**
   - **面數控制在數百到一千多三角面**（天鷹段整段展示區約 **718 triangles**）：
     - 管線改用 **6 邊圓柱**（`vertices=6`）。
     - 垂墜電線用 **雙點折線片**（扁平細帶，不用高面數 Curve 圓管）。
     - 浪板／格柵直接用 **折線摺痕網格**（zig-zag 單面群）搭配貼圖陰影。
   - 可參考已驗證腳本：[tools/aquila_ps2_build.py](tools/aquila_ps2_build.py)。
4. **進 Godot 組裝與驗證**
   - 將 `.glb` 實例化到對應 `@tool` 場景腳本（不可設 `owner`），補上 `CollisionShape3D`、非陰影柔和補光，以及水波反光貼片。
   - 在 Godot 內實機測試「出生點視角」與「低頭斜視地面」，確認無破圖、無深度閃爍（Z-fighting）與報錯後，再 `git commit` 留存檔點。

---

## 二、座標軸與碰撞換算（Blender → glTF → Godot）

Blender 匯出 `.glb`（預設勾選 `export_yup=True`）後，座標對應為：

| Blender 軸向 | Godot 軸向 | 遊戲內方向意義 |
|---|---|---|
| `+X` | `+X` | 玩家右側 |
| `+Z` | `+Y` | 垂直向上 |
| `+Y` | `-Z` | **玩家正前方（面朝方向）** |

- **文字／圖案貼面朝向**：面向玩家正前方的圖案（如柱子上的 `F`）應畫在 Blender 的 `-Y` 面（匯入 Godot 後即為 `+Z` 面）。
- **斜坡可走碰撞體傾斜角**：斜坡從近端低處往 `-Z` 方向升高時，在 Godot 的 `CollisionShape3D` 旋轉角為：
  `rotation.x = atan2(上升高度差, 水平長度)`（正值會把 `-Z` 端抬高）。

---

## 三、128px PS2 像素貼圖與質感設定

1. **貼圖規格**：
   - 使用 `128×128`（方柱／牆面）或 `128×256`（長條地板）PNG。
   - 色彩做低飽和與小幅色階量化（posterize），模擬 PS2 16-bit 顆粒感。
   - 若要表現積水／乾濕對比，額外輸出一張黑白 **Roughness 貼圖**（乾水泥約 `0.90` 白色、積水與輪胎痕約 `0.07` 深灰黑）。
2. **Godot 材質強制不糊化**：
   - 匯入 `.glb` 後，在程式內走訪子節點 `MeshInstance3D`，將複製出的 `StandardMaterial3D` 設為：
     `sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST`
   - 若為濕滑地面材質，可適度提高 `sm.metallic`（約 `0.28`）與 `sm.metallic_specular`（約 `0.88`），讓燈條與手電筒照到水窪時能清楚反光。
3. **反射探針順序**：
   - `ReflectionProbe`（`UPDATE_ONCE`）必須在模型與發光燈條都建立**之後**再加進場景，這樣探針烘焙反射時才吃得到新柱子與白燈條的倒影。

---

## 四、Blender 5.3 與 無頭（Headless）腳本踩坑紀錄

1. **不要直接 `.get("Principled BSDF")`**：
   - 在 Blender 5.3（特別是中文介面環境）可能回傳 `None`。請一律先 `nt.nodes.clear()`，再用 `nt.nodes.new("ShaderNodeBsdfPrincipled")` 重建節點並連接到 `ShaderNodeOutputMaterial`。
2. **Blender 程式雜訊不會自動匯出進 `.glb`**：
   - `ShaderNodeTexNoise`、`ShaderNodeValToRGB` 等節點在 glTF 匯出時會失效；必須輸出成實際 PNG 並接上 `ShaderNodeTexImage`（設定 `interpolation = 'Closest'`）後再 `pack()` 進 `.glb`。
3. **無頭模式下用 `bpy.data.images.new` 存 PNG 可能變全黑**：
   - 在 headless 批次腳本中，改用 Python 標準庫 `zlib` + `struct` 先把 RGBA numpy 陣列直接寫出標準 `.png` 檔案，再用 `bpy.data.images.load(path)` 載入與 `pack()`，可確保貼圖像素 100% 正確。
4. **不要在 `blender-mcp` 連線中呼叫 `read_factory_settings(use_empty=True)`**：
   - 該指令會把正在運行的 `blender_mcp` 外掛連線中斷。若需乾淨白紙環境批量建模型與匯出，改用命令列無頭執行：
     `blender.exe -b --factory-startup --python <script.py>`
5. **Blender 5.x 合成器節點變動**：
   - 舊版 `CompositorNodeGlare.glare_type` 與 `CompositorNodeComposite` 在 5.3 會報錯；合成器發光建議另查 5.x 輸入插槽，或直接進 Godot 由材質自發光＋光影表現。

---

## 五、防地板閃爍（Z-fighting）與效能鐵則

在 PS2 低解析度後製視口下，深度緩衝精度有限，**最容易發生兩片地板重疊閃爍（對角線撕裂）**：

1. **直接挖空底層重疊視覺網格**：
   - 若某區域改用 Blender 匯出的專屬地面（如天鷹段中央展示區 `x: -6.8..4.3, z: -17.5..3.5`），**必須把原本的大地磚視覺盒在該範圍挖空切開**，只保留一整片完整的無形 `CollisionShape3D` 碰撞箱。底下沒有重疊面就絕對不會打架。
2. **細分長條地面網格**：
   - 超過 10 公尺的地面不要只用單一 4 頂點矩形，至少細分成 `4×8` 等級的小格，減少遠近深度誤差。
3. **貼花與水波片拉開安全間距**：
   - 停車線、警告條等舊裝飾應避開覆蓋新地面座標；透明水波貼片（`puddle_water.gdshader`）至少架高 **`0.02 m`（2 公分）以上**。
4. **燈光與命名規範**：
   - 遵守 [AGENTS.md](AGENTS.md) 第 4 條：新區段補光一律關閉即時陰影（`shadow_enabled = false`），只保留極少數關鍵主燈開陰影。
   - 遊戲內所有介面、地圖傳送點、紙條與檔案庫**一律使用層級與區段名稱**（如「閾界」、「宜居地帶」、「天鷹段」），不出現 `Level 0` / `Level 1` 編號。
