plugins {
    id("ru.vyarus.animalsniffer")
    alias(libs.plugins.kotlin.jvm)
}
kotlin { jvmToolchain(21) }
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}
tasks.withType<JavaCompile>().configureEach { options.release.set(17) }
dependencies {
    implementation(libs.okhttp)
    implementation(libs.coroutines)
    implementation(libs.json)
    testImplementation(libs.junit)
    testImplementation(libs.mockwebserver)
}

// Optional external synthetic WAV evidence; an explicitly supplied missing fixture fails.
tasks.withType<Test>().configureEach {
    systemProperty("paply.shared.polish", rootProject.file("../shared/polish").absolutePath)
    providers.gradleProperty("paply.regression.fixtures").orNull?.let {
        systemProperty("paply.regression.fixtures", it)
    }
}

// JVM compilation uses JDK 21; check emitted bytecode against the real Android floor.
// Unit tests run on the host JVM and intentionally may use newer host APIs.
animalsniffer { sourceSets = listOf(project.sourceSets.main.get()) }
dependencies {
    add("signature", "com.toasttab.android:gummy-bears-api-29:0.14.0@signature")
}
tasks.named("test") { dependsOn("animalsnifferMain") }
