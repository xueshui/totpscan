plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("maven-publish")
}

val sdkGroup = providers.gradleProperty("scanTotp.group").getOrElse("com.scanauth")
val sdkArtifact = providers.gradleProperty("scanTotp.artifact").getOrElse("scan-totp-sdk")
val sdkVersion = providers.gradleProperty("scanTotp.version").getOrElse("1.0.0")

android {
    namespace = "com.scanauth.sdk"
    compileSdk = 35
    buildToolsVersion = "35.0.1"

    defaultConfig {
        minSdk = 23
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    testOptions {
        unitTests.all { it.useJUnit() }
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

dependencies {
    // EncryptedSharedPreferences 依赖 Android Keystore 主密钥（不可导出）。
    api("androidx.security:security-crypto:1.1.0-alpha06")

    testImplementation("junit:junit:4.13.2")
    // Android 单元测试默认使用 android.jar 中的 org.json 桩实现，这里引入真实实现以便测试解析逻辑。
    testImplementation("org.json:json:20240303")
}

publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = sdkGroup
            artifactId = sdkArtifact
            version = sdkVersion
            afterEvaluate { from(components["release"]) }
            pom {
                name.set("Scan-TOTP Android SDK")
                description.set("扫码增强型 TOTP 认证 SDK：绑定固化提交地址，登录仅向本地固化 HTTPS 地址提交动态码。")
                url.set("https://example.invalid/scan-totp")
                licenses {
                    license {
                        name.set("Proprietary")
                    }
                }
            }
        }
    }
    repositories {
        maven {
            name = "dist"
            url = uri(rootProject.layout.buildDirectory.dir("maven-dist").get().asFile)
        }
    }
}
