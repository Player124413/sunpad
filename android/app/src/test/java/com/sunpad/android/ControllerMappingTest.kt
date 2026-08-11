package com.sunpad.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Regression mirror of tests/SunPadControllerMappingTests.mm for the pure
 * Android port of the controller mapping logic (no Android framework needed).
 */
class ControllerMappingTest {

    private fun assertMappingsEqual(expected: ButtonMapping, actual: ButtonMapping) {
        assertEquals(expected, actual)
    }

    @Test
    fun defaultsAreValidAndApply() {
        val defaults = ControllerMapping.default()
        assertTrue(defaults.isValid())
        assertEquals(
            SunPadButtons.A or SunPadButtons.Z,
            ControllerMapping.applyMapping(
                defaults,
                PhysicalButton.A.bit or PhysicalButton.RIGHT_SHOULDER.bit))
    }

    @Test
    fun assigningSwaps() {
        val mapping = ControllerMapping.assign(
            ControllerMapping.default(), PhysicalButton.B, SunPadButtons.A)
        assertEquals(PhysicalButton.B, mapping.gameA)
        assertEquals(PhysicalButton.A, mapping.gameB)
        assertEquals(
            SunPadButtons.A or SunPadButtons.B,
            ControllerMapping.applyMapping(
                mapping,
                PhysicalButton.A.bit or PhysicalButton.B.bit))
    }

    @Test
    fun corruptMappingFallsBackToDefaults() {
        val corrupt = ControllerMapping.default().copy(gameZ = PhysicalButton.B)
        assertFalse(corrupt.isValid())
        assertEquals(
            SunPadButtons.Z,
            ControllerMapping.applyMapping(corrupt, PhysicalButton.RIGHT_SHOULDER.bit))
    }

    @Test
    fun assigningSameButtonIsNoOp() {
        val defaults = ControllerMapping.default()
        val mapping = ControllerMapping.assign(
            defaults, PhysicalButton.A, SunPadButtons.A)
        assertMappingsEqual(defaults, mapping)
    }

    @Test
    fun invalidMappingAssignmentRepairsFirst() {
        val corrupt = ControllerMapping.default().copy(gameZ = PhysicalButton.B)
        val repaired = ControllerMapping.assign(
            corrupt, PhysicalButton.Y, SunPadButtons.A)
        assertTrue(repaired.isValid())
        assertEquals(PhysicalButton.Y, repaired.gameA)
    }
}
