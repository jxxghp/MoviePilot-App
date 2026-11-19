"""验证迁移范围扫描器不会静默漏记路由、把字符串注释当组件或运行插件。"""

import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location(
    "native_inventory", Path(__file__).resolve().parents[1] / "native-v2-inventory.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class NativeInventoryTests(unittest.TestCase):
    """使用合成源码验证扫描边界，不访问工作区以外的仓库或网络。"""

    def test_routes_keep_distinct_entries_for_a_shared_page(self):
        """电影和电视剧订阅共用一个源文件，仍必须保留两项验收入口。"""
        routes = MODULE.frontend_routes("""
        {
          path: '/subscribe/movie',
          component: () => import('../pages/subscribe/index.vue'),
          meta: { permission: 'subscribe', feature: PERMISSION_FEATURE.SUBSCRIBE_MOVIE },
        },
        {
          path: '/subscribe/tv',
          component: () => import('../pages/subscribe/index.vue'),
          meta: { permission: 'subscribe', feature: PERMISSION_FEATURE.SUBSCRIBE_TV },
        },
        """)
        self.assertEqual([r["path"] for r in routes], ["/subscribe/movie", "/subscribe/tv"])
        self.assertEqual([r["feature"] for r in routes], ["SUBSCRIBE_MOVIE", "SUBSCRIBE_TV"])

    def test_unknown_route_shape_requires_an_update(self):
        """失去字面量路径时应要求人工更新，不能输出看似完整的空清单。"""
        with self.assertRaises(ValueError):
            MODULE.frontend_routes("component: () => import('../pages/site.vue')")

    def test_plugin_scan_uses_ast_without_executing_the_module(self):
        """构造函数、方法和注释都不会被执行或误报为真实字面量组件。"""
        components, methods = MODULE.plugin_symbols("""
raise RuntimeError("never execute this")
# "component": "FakeWidget"
def get_form():
    return [{"component": "VSwitch"}, {"component": choose_widget()}]
""")
        self.assertEqual(components, ["VSwitch"])
        self.assertEqual(methods, ["get_form"])

    def test_endpoint_scan_is_explicitly_a_declaration_count(self):
        """多行与异步装饰器参与计数，普通函数调用不算路由声明。"""
        counts = MODULE.endpoint_counts("""
@router.get(
    "/list"
)
async def items(): pass
@router.post("/save")
def save(): pass
client.get("/not-an-endpoint")
""")
        self.assertEqual(counts, {"GET": 1, "POST": 1})


if __name__ == "__main__":
    unittest.main()
