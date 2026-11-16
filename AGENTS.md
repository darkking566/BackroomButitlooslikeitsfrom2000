# 貝克潤PS2 — AI 與專案協作規則

1. **不要直接手改 `.tscn` 的 `unique_id` 或刪除 `.uid` 檔**
   - 場景結構與節點變更優先透過 `godot-mcp-toolkit`（由 Godot 編輯器本身處理）進行，避免破壞資源引用。
2. **避免與使用者同時編輯同一個檔案**
   - 若使用者剛在 Godot 編輯器裡手動改過場景或設定，請先請使用者存檔（`Ctrl+S`）後再由 AI 接手修改。
3. **`@tool` 程式生成節點不可設定 `owner`**
   - [scripts/backrooms_maze.gd](scripts/backrooms_maze.gd) 與 [scripts/zone2_hall.gd](scripts/zone2_hall.gd) 在編輯器內生成的幾何體與燈光不可指派 `owner`，以免存檔時被序列化寫入 `.tscn`。
4. **控制即時陰影數量**
   - 本專案為 PS1/PS2 復古風格，迷宮與大廳只保留少量關鍵燈源開啟 `shadow_enabled = true`，其餘燈光維持關閉以兼顧效能與復古質感。
5. **打包發布（Export）前移除開發工具**
   - 正式輸出遊戲前，需停用 `addons/godot_mcp_toolkit` 外掛並移除 `project.godot` 中的 `MCPRuntimeServer` 自動載入。
6. **每個階段完成後建立 Git 存檔點**
   - 每次完成一個可驗證的功能或修復後，執行一次本地 `git commit` 留下還原點（不主動 push 到遠端）。
