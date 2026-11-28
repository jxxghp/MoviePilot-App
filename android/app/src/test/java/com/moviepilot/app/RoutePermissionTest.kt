package com.moviepilot.app

import com.moviepilot.rustcore.PermissionsFfi
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/** 原生入口与后端 manage/admin 权限边界一致。 */
class RoutePermissionTest {
    /** 有管理权限的普通账号可进入站点和工作流，不能进入超级管理员用户管理。 */
    @Test fun manageUserCanOpenManageRoutes() {
        val permissions = PermissionsFfi(false, false, false, true, false)
        assertNull(checkRoutePermission(AppRoute.Sites, permissions))
        assertNull(checkRoutePermission(AppRoute.Workflows, permissions))
        assertNotNull(checkRoutePermission(AppRoute.Users, permissions))
    }

    /** 缺少 manage 的普通账号仍被拦截，超级管理员维持既有全权限。 */
    @Test fun deniedAndAdministratorRoutesRemainProtected() {
        assertNotNull(checkRoutePermission(AppRoute.Workflows, PermissionsFfi(true, true, true, false, false)))
        assertNull(checkRoutePermission(AppRoute.Users, PermissionsFfi(false, false, false, false, true)))
    }

    /** 非超级管理员即使无任何业务子权限，也可进入设置与个人媒体服务器账号绑定，而实例级媒体服务器配置仍受保护。 */
    @Test fun nonAdminCanAccessSettingsAndPersonalMediaServerAccountBindings() {
        val memberPermissions = PermissionsFfi(false, false, false, false, false)
        assertNull(checkRoutePermission(AppRoute.SettingsHub, memberPermissions))
        assertNull(checkRoutePermission(AppRoute.MediaServerAccountBindings, memberPermissions))
        assertNotNull(checkRoutePermission(AppRoute.MediaServersSettings, memberPermissions))
    }
}
