// Apps nativas de Android de Grupo XD (Botaniker Alchemist S.A.S.): maXD (equipo) y Bodega XD (clientes).
// Las dos son el mismo "cascarón": muestran el sistema web y reciben los avisos por Firebase Cloud Messaging.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val numero = (System.getenv("NUMERO_BUILD") ?: "1").toInt()
val llaveFirebase = System.getenv("FIREBASE_API_KEY") ?: ""

android {
    namespace = "com.xdcuenca.shell"
    compileSdk = 35
    defaultConfig {
        minSdk = 24
        targetSdk = 35
        versionCode = 100 + numero
        buildConfigField("String", "FIREBASE_API_KEY", "\"$llaveFirebase\"")
        buildConfigField("String", "FIREBASE_PROJECT", "\"cuadre-xd\"")
        buildConfigField("String", "FIREBASE_SENDER", "\"2904773404\"")
    }
    flavorDimensions += "app"
    productFlavors {
        create("maxd") {
            dimension = "app"
            applicationId = "com.xdcuenca.maxd"
            versionName = "1.0.1"
            buildConfigField("String", "SISTEMA", "\"https://maxdec.netlify.app/?app=staff\"")
            buildConfigField("String", "MARCA_UA", "\"maXD-Android/2.0\"")
            buildConfigField("String", "FIREBASE_APP_ID", "\"1:2904773404:android:aee566febdf508bfa460d9\"")
            buildConfigField("String", "HOSTS_PROPIOS", "\"maxdec.netlify.app,xdecuador.com\"")
        }
        create("bodega") {
            dimension = "app"
            applicationId = "com.xdcuenca.app"
            versionName = "1.1.0"
            buildConfigField("String", "SISTEMA", "\"https://xdecuador.com/?app=tienda\"")
            buildConfigField("String", "MARCA_UA", "\"BodegaXD-Android/2.0\"")
            buildConfigField("String", "FIREBASE_APP_ID", "\"1:2904773404:android:d5087ca3c762cec7a460d9\"")
            buildConfigField("String", "HOSTS_PROPIOS", "\"xdecuador.com,maxdec.netlify.app\"")
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    buildFeatures { buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.webkit:webkit:1.12.1")
    implementation(platform("com.google.firebase:firebase-bom:33.5.1"))
    implementation("com.google.firebase:firebase-messaging")
}
