plugins {
    id("ru.vyarus.animalsniffer")
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin { jvmToolchain(21) }

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}

tasks.withType<JavaCompile>().configureEach { options.release.set(17) }

dependencies {
    implementation(project(":core"))
    implementation("com.github.rholder:snowball-stemmer:1.3.0.581.1")
    implementation(libs.okhttp)
    implementation(libs.coroutines)
    implementation(libs.json)
    testImplementation(libs.junit)
    testImplementation(libs.mockwebserver)
}

// JVM compilation uses JDK 21; check emitted bytecode against the real Android floor.
// Unit tests run on the host JVM and intentionally may use newer host APIs.
animalsniffer { sourceSets = listOf(project.sourceSets.main.get()) }
dependencies {
    add("signature", "com.toasttab.android:gummy-bears-api-29:0.14.0@signature")
}
tasks.named("test") { dependsOn("animalsnifferMain") }

tasks.withType<Test>().configureEach {
    systemProperty("paply.shared.thoughts", rootProject.file("../shared/gedanken").absolutePath)
}
