import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// 签名材料不入库。读取顺序：
//   1. 环境变量 ANDROID_KEYSTORE_PATH / ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD
//   2. 本地文件 android/keystore.local.properties（已被 .gitignore 排除）
// release 构建缺少任一材料时直接失败，不静默退回未签名或 debug 签名。
val localSigningFile = rootProject.file("keystore.local.properties")
val localSigning = Properties().apply {
    if (localSigningFile.exists()) localSigningFile.inputStream().use { load(it) }
}

fun signingValue(envName: String, key: String): String? =
    System.getenv(envName)?.takeIf { it.isNotBlank() }
        ?: localSigning.getProperty(key)?.takeIf { it.isNotBlank() }

val keystorePathValue = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")
val storePasswordValue = signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
val keyAliasValue = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
val keyPasswordValue = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")

val keystoreFile = keystorePathValue?.let { raw ->
    val fromRoot = rootProject.file(raw)
    when {
        File(raw).isAbsolute -> File(raw)
        fromRoot.exists() -> fromRoot
        else -> file(raw)
    }
}?.takeIf { it.exists() }

val hasReleaseSigning = keystoreFile != null &&
    storePasswordValue != null && keyAliasValue != null && keyPasswordValue != null

val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
if (releaseRequested && !hasReleaseSigning) {
    throw GradleException(
        "release 构建需要签名材料，但配置不完整。\n" +
            "请通过环境变量 ANDROID_KEYSTORE_PATH / ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD 提供，\n" +
            "或在 android/keystore.local.properties 中配置 storeFile / storePassword / keyAlias / keyPassword。\n" +
            "签名证书与口令不得提交到版本库。"
    )
}

android {
    namespace = "com.scanauth.app"
    compileSdk = 35
    buildToolsVersion = "35.0.1"

    defaultConfig {
        applicationId = "com.scanauth.app"
        minSdk = 23
        targetSdk = 35
        versionCode = 3
        versionName = "1.0.2"
        // 只保留中文与英文资源，避免无用体积
        resourceConfigurations += listOf("zh", "en")
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = keystoreFile
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        debug {
            applicationIdSuffix = ".debug"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }

    packaging {
        resources.excludes += setOf("/META-INF/{AL2.0,LGPL2.1}")
    }
}

dependencies {
    implementation(project(":sdk"))

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.navigation:navigation-compose:2.8.4")
    implementation("androidx.biometric:biometric:1.1.0")

    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")

    val cameraX = "1.4.0"
    implementation("androidx.camera:camera-core:$cameraX")
    implementation("androidx.camera:camera-camera2:$cameraX")
    implementation("androidx.camera:camera-lifecycle:$cameraX")
    implementation("androidx.camera:camera-view:$cameraX")

    // 纯 Java 的二维码解码库，不依赖 Google Play Services
    implementation("com.google.zxing:core:3.5.3")

    testImplementation("junit:junit:4.13.2")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
