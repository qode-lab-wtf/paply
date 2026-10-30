package com.paply.core;

import org.junit.Test;
import static org.junit.Assert.*;

/** Runs the actual core helper on Android ICU, not a second Java regex implementation. */
public class PatternDeviceTest {
    @Test public void unicodeWordBoundaries() {
        Pattern p = new Pattern("\\büber\\b", true);
        assertTrue(p.matches("Äpfel über Öl"));
        assertFalse(p.matches("darüber übermorgen"));
        assertEquals(2, p.count("ÜBER, über!"));
        assertEquals("Öl x Öl", p.replacing("Öl über Öl", "x"));
    }
    @Test public void unicodeCaseAndGroups() {
        assertTrue(new Pattern("\\bäpfel\\b", true).matches("ÄPFEL"));
        assertEquals("ÖL", new Pattern("(öl)", true).firstGroup("ÖL", 1));
        assertFalse(new Pattern("äpfel", false).matches("ÄPFEL"));
    }
    @Test public void dollarEndAndLiteralReplacement() {
        Pattern p = new Pattern("Ende$", false);
        assertTrue(p.matches("Ende"));
        assertTrue(p.matches("Ende\n"));
        assertFalse(p.matches("Ende mehr"));
        assertEquals("$5\\weg", p.replacingFirst("Ende", "$5\\weg"));
        assertEquals("Preis 5$", new Pattern("EUR$", false).replacing("Preis 5EUR", "\\$"));
    }
}
