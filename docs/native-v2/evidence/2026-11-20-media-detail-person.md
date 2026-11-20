# P3.4 完整原生影视详情与演职员/人物页验收证据

- 日期：2026-11-20
- 分支：`MoviePilot-App` / `v2`
- 目标范围：补齐电影与电视剧完整原生详情页（全宽背景头图、入库状态徽标、权限门控的显式订阅与二次确认取消、剧集分季海报与单季独立订阅、演职员圆形头像横栏、相似/推荐横栏、作品资料卡），以及可由详情页与搜索页原生推入的人物详情与参演作品网格页。

## 主要实现面

- `ios/MoviePilot/NativeV2/Pages/NativeMediaDetailPage.swift`：
  - `NativeMediaDetailPage`：直连 `GET /api/v1/media/{id}`、`POST /api/v1/media/status`、`GET /api/v1/tmdb/credits/{id}/{type}`、`GET /api/v1/tmdb/recommend/{id}/{type}`（为空时回落 `similar`）、`POST /api/v1/subscribe/`（单次提交、不自动重试）与 `DELETE /api/v1/subscribe/media/{id}`（弹层二次确认）。
  - 相对 TMDB 路径（`season_info.poster_path`、`profile_path`）经安全白名单补全后统一走同源受控图片代理 `/api/v1/system/img/0`。
  - `NativePersonDetailPage`：直连 `GET /api/v1/tmdb/person/{id}` 与 `GET /api/v1/tmdb/person/credits/{id}`，呈现圆形肖像、履历、可展开简介与三列参演作品网格，并支持继续推入影视详情。
- `ios/MoviePilot/NativeV2/NativeMediaSearchPage.swift`：搜索人物圆形头像支持直接推入 `NativePersonDetailPage`。
- `scripts/native-v2-fixture.py` & `scripts/tests/test_native_v2_fixture.py`：补齐 `media/status`、`tmdb/credits|recommend|similar|person|person/credits` 与 `subscribe` 增删夹具及单元测试。

## 验证记录

1. **脚本与格式检查**
   - `python3 -m unittest discover -s scripts/tests`：27/27 通过。
   - `xcrun swift-format lint --strict`：0 错误。
   - 全仓文本敏感命名检查：0 匹配。
2. **本机 3001 真实后端只读验收（`scripts/native-v2-live.py`）**
   - 结果：`{"result": "Passed", "passedTests": 1, "failedTests": 0, "skippedTests": 0, "backend": "http://127.0.0.1:3001/"}`。
   - 逐张视觉复核实图：电影详情（`坠落 2：死点`，含标语/时长/分级/评分/风格胶囊/订阅主按钮/简介）、演职员圆形头像与相似推荐、人物详情及参演作品网格（`哈里特·斯莱特`）、电视剧详情与分季卡片（`超感神探` 第 1–5 季海报与独立订阅按钮），全部符合单一深色渐变玻璃视觉标准，且 `webViews.count == 0`。
3. **API-only 合成夹具全链路 UI 验收（`testNativeMediaDetailSubscribesAndNavigatesToPerson`）**
   - **iPhone 17**：1/1 通过（73.21s），覆盖入库徽标、电影显式订阅、取消确认弹窗与 `DELETE`、演职员跳转人物页、人物参演作品跳转剧集详情与分季独立订阅，`unexpected == [:]`，`webViews.count == 0`。
   - **iPad Pro 11-inch (M5)**：1/1 通过（68.87s），全链路断言与请求计数一致。

## 未覆盖与后续叶子

- 资源搜索与下载确认（`/resource`）归入 **P3.3b**；媒体库内播放直连原生播放器归入 **P7.3**；下载任务列表、订阅管理与日历转入下一激活叶子 **P5.1 / P4.1 / P4.4**。
