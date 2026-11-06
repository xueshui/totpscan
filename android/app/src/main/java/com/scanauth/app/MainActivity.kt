package com.scanauth.app

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.scanauth.app.ui.AccountDetailScreen
import com.scanauth.app.ui.AddAccountScreen
import com.scanauth.app.ui.AddStandardScreen
import com.scanauth.app.ui.BindConfirmScreen
import com.scanauth.app.ui.ExportQrScreen
import com.scanauth.app.ui.HomeScreen
import com.scanauth.app.ui.LoginScreen
import com.scanauth.app.ui.ScanScreen
import com.scanauth.app.ui.SettingsScreen
import com.scanauth.app.ui.theme.ScanTotpTheme

/**
 * 应用入口。
 *
 * 使用 FragmentActivity 而非 ComponentActivity，是因为生物识别门禁依赖
 * `androidx.biometric.BiometricPrompt` 的 Fragment 生命周期。
 */
class MainActivity : FragmentActivity() {

    private val viewModel: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val settings by viewModel.settings.collectAsStateWithLifecycle()
            ScanTotpTheme(mode = settings.theme) {
                AppNavHost(viewModel = viewModel, activity = this)
            }
        }
    }
}

private object Routes {
    const val HOME = "home"
    const val ADD = "add"
    const val ADD_STANDARD = "add_standard/{mode}"
    const val SCAN = "scan/{mode}"
    const val BIND_CONFIRM = "bind_confirm"
    const val LOGIN = "login"
    const val ACCOUNT = "account/{localId}"
    const val EXPORT_QR = "export_qr/{localId}"
    const val SETTINGS = "settings"

    fun addStandard(mode: String) = "add_standard/$mode"
    fun scan(mode: String) = "scan/$mode"
    fun account(localId: String) = "account/$localId"
    fun exportQr(localId: String) = "export_qr/$localId"
}

@Composable
private fun AppNavHost(viewModel: AppViewModel, activity: FragmentActivity) {
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = Routes.HOME) {
        composable(Routes.HOME) {
            HomeScreen(
                viewModel = viewModel,
                onOpenSettings = { navController.navigate(Routes.SETTINGS) },
                onAddAccount = { navController.navigate(Routes.ADD) },
                onScanLogin = { navController.navigate(Routes.scan("login")) },
                onOpenAccount = { localId -> navController.navigate(Routes.account(localId)) }
            )
        }

        composable(Routes.ADD) {
            AddAccountScreen(
                onBack = { navController.popBackStack() },
                onScanBind = { navController.navigate(Routes.scan("bind")) },
                onManualInput = { navController.navigate(Routes.addStandard("manual")) },
                onOtpauthImport = { navController.navigate(Routes.addStandard("uri")) }
            )
        }

        composable(
            route = Routes.ADD_STANDARD,
            arguments = listOf(navArgument("mode") { type = NavType.StringType })
        ) { entry ->
            val mode = entry.arguments?.getString("mode") ?: "manual"
            AddStandardScreen(
                mode = mode,
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
                onDone = { navController.popBackStack(Routes.HOME, inclusive = false) }
            )
        }

        composable(
            route = Routes.SCAN,
            arguments = listOf(navArgument("mode") { type = NavType.StringType })
        ) { entry ->
            when (entry.arguments?.getString("mode")) {
                "bind" -> ScanScreen(
                    title = "扫描绑定二维码",
                    subtitle = "将二维码放入框内。识别成功后还需你确认提交地址，才会保存到本机。",
                    onBack = { navController.popBackStack() },
                    onPayload = { payload ->
                        viewModel.resetBind()
                        viewModel.beginBind(payload)
                        navController.navigate(Routes.BIND_CONFIRM) {
                            popUpTo(Routes.scan("bind")) { inclusive = true }
                        }
                    }
                )

                else -> ScanScreen(
                    title = "扫描登录二维码",
                    subtitle = "只会在本机已绑定该服务器的账户中提交，扫描结果需要你确认。",
                    onBack = { navController.popBackStack() },
                    onPayload = { payload ->
                        viewModel.resetLogin()
                        viewModel.beginLogin(payload)
                        navController.navigate(Routes.LOGIN) {
                            popUpTo(Routes.scan("login")) { inclusive = true }
                        }
                    }
                )
            }
        }

        composable(Routes.BIND_CONFIRM) {
            BindConfirmScreen(
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
                onDone = { navController.popBackStack(Routes.HOME, inclusive = false) }
            )
        }

        composable(Routes.LOGIN) {
            LoginScreen(
                viewModel = viewModel,
                activity = activity,
                onBack = { navController.popBackStack() },
                onDone = { navController.popBackStack(Routes.HOME, inclusive = false) }
            )
        }

        composable(
            route = Routes.ACCOUNT,
            arguments = listOf(navArgument("localId") { type = NavType.StringType })
        ) { entry ->
            val localId = entry.arguments?.getString("localId").orEmpty()
            AccountDetailScreen(
                localId = localId,
                viewModel = viewModel,
                activity = activity,
                onExportQr = { id -> navController.navigate(Routes.exportQr(id)) },
                onBack = { navController.popBackStack() }
            )
        }

        composable(
            route = Routes.EXPORT_QR,
            arguments = listOf(navArgument("localId") { type = NavType.StringType })
        ) { entry ->
            val localId = entry.arguments?.getString("localId").orEmpty()
            ExportQrScreen(
                localId = localId,
                viewModel = viewModel,
                activity = activity,
                onClose = { navController.popBackStack() }
            )
        }

        composable(Routes.SETTINGS) {
            SettingsScreen(
                viewModel = viewModel,
                activity = activity,
                onBack = { navController.popBackStack() }
            )
        }
    }
}
