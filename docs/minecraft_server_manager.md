# Minecraft 模組伺服器自動管理腳本

`scripts/minecraft_server_manager.sh` 是一個用 Bash 撰寫的 Minecraft Java 伺服器管理腳本，
提供以下功能：

- 自動偵測 `java` 並啟動模組化伺服器 (`nogui` 模式)。
- 伺服器異常結束後自動重啟，並在每次重啟前後建立備份。
- 於背景定期備份世界存檔，並提供備份輪替 (保留指定數量的備份)。
- 接收 `SIGINT` / `SIGTERM` 時會停止伺服器與備份排程，並確保安全退出。
- 透過建立 `stop.txt` (可自訂) 來通知腳本停止重啟循環。

> **注意**：此腳本假設伺服器目錄中有可直接啟動的 `server.jar`（或自行指定）。
> 建議搭配 `rsync` 取得最佳備份效能，若系統無 `rsync` 會改用 `cp -a`。

## 安裝與使用

1. 先確定系統已安裝 Java 17 (或伺服器所需版本)。
2. 將 `scripts/minecraft_server_manager.sh` 複製到伺服器主機並賦予可執行權限：

   ```bash
   chmod +x scripts/minecraft_server_manager.sh
   ```

3. 將腳本放在 Minecraft 伺服器目錄下執行，或透過環境變數覆寫路徑：

   ```bash
   SERVER_DIR=/opt/mc SERVER_JAR=fabric-server-launch.jar \
   BACKUP_INTERVAL_MINUTES=20 MAX_BACKUPS=72 \
   scripts/minecraft_server_manager.sh
   ```

   也可以在伺服器目錄建立 `.env` 或 `.minecraft-server.env` 來保存參數，腳本啟動時會自動載入。

   常用環境變數如下：

   | 變數 | 預設值 | 說明 |
   | ---- | ------ | ---- |
   | `SERVER_DIR` | 目前工作目錄 | 伺服器所在目錄。 |
   | `SERVER_JAR` | `server.jar` | 要啟動的伺服器 JAR。 |
   | `JAVA_CMD` | `java` | Java 執行檔路徑。 |
   | `JAVA_ARGS` | `-Xms2G -Xmx2G` | JVM 參數。 |
   | `WORLD_DIR` | `$SERVER_DIR/world` | 世界存檔目錄。 |
   | `BACKUP_DIR` | `$SERVER_DIR/backups` | 備份儲存目錄。 |
   | `BACKUP_INTERVAL_MINUTES` | `30` | 定期備份的分鐘間隔。 |
   | `MAX_BACKUPS` | `48` | 最多保留的備份數量 (0 表示不刪除舊備份)。 |
   | `RESTART_DELAY` | `10` | 伺服器重新啟動前等待秒數。 |
   | `STOP_FILE` | `$SERVER_DIR/stop.txt` | 建立此檔案即可讓腳本在下一輪停止。 |
   | `LOG_DIR` | `$SERVER_DIR/logs` | 伺服器與腳本輸出紀錄目錄。 |

4. 於伺服器運行期間欲停止自動重啟，可建立 stop 檔案或傳送 `CTRL+C`：

   ```bash
   touch /opt/mc/stop.txt
   ```

5. 備份會依 `world-YYYYmmdd-HHMMSS` 命名放在 `BACKUP_DIR` 內，可自行上傳至遠端儲存。

## 進階建議

- 若使用 Fabric/Forge 模組伺服器，請確保相容的 `server.jar` 已產生。
- 建議於 `server.properties` 啟用 `sync-chunk-writes=true` 以降低備份時的資料競爭。
- 可透過 systemd、tmux 或 Docker 將此腳本整合進既有的部署流程。

## 疑難排解

- **腳本找不到 Java**：確認 `JAVA_CMD` 指向正確的 Java 路徑或更新 PATH。
- **備份耗時過久**：安裝 `rsync` 或調整備份間隔、保留數量。
- **伺服器立即關閉**：檢查 `latest.log` 或腳本輸出 (`logs/server-YYYYmmdd.log`) 以取得詳細訊息。

