package com.paply.core
import java.io.File
import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Test

class SharedTermTests {
    @Test fun survivesPolish() {
        assertEquals(null, PolishSafetyNet.rejection("hallo Law Min wie geht es dir","Hallo Law Min, wie geht es dir?", vocabulary = "Law Min"))
    }
    @Test fun sharedCases() {
        val cases = Json.parseToJsonElement(File(File(checkNotNull(System.getProperty("paply.shared.language"))).parentFile, "begriffe/faelle.json").readText()).jsonObject
        for (item in cases.getValue("klang").jsonArray) {
            val c = item.jsonObject
            assertEquals(c.getValue("name").jsonPrimitive.content, c.getValue("near").jsonPrimitive.boolean,
                TermGuard.near(c.getValue("term").jsonPrimitive.content,c.getValue("text").jsonPrimitive.content))
        }
        for (item in cases.getValue("annahme").jsonArray) {
            val c = item.jsonObject
            fun str(k: String) = c.getValue(k).jsonPrimitive.content
            assertEquals(str("name"), c.getValue("accept").jsonPrimitive.boolean,
                TermGuard.accept(str("term"),str("first"),str("second"),c["lpFirst"]?.jsonPrimitive?.doubleOrNull,c["lpSecond"]?.jsonPrimitive?.doubleOrNull))
        }
    }
}
