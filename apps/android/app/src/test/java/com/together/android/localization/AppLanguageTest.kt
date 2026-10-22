package com.together.android.localization

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.Locale
import javax.xml.parsers.DocumentBuilderFactory

class AppLanguageTest {
    @Test fun explicitSelectionSurvivesSystemLanguageChanges() {
        assertEquals(AppLanguage.ENGLISH, AppLanguage.initial("en", Locale.SIMPLIFIED_CHINESE))
        assertEquals(AppLanguage.CHINESE, AppLanguage.initial("zh-CN", Locale.ENGLISH))
    }

    @Test fun firstRunUsesChineseForEveryChineseSystemVariantAndEnglishOtherwise() {
        listOf("zh-CN", "zh-TW", "zh-HK", "zh-Hans", "zh-Hant").forEach {
            assertEquals(it, AppLanguage.CHINESE, AppLanguage.initial(null, Locale.forLanguageTag(it)))
        }
        listOf("en-US", "en-GB", "fr-FR", "ja-JP").forEach {
            assertEquals(it, AppLanguage.ENGLISH, AppLanguage.initial(null, Locale.forLanguageTag(it)))
        }
        assertEquals(AppLanguage.ENGLISH, AppLanguage.initial("unsupported", Locale.ENGLISH))
        assertEquals(setOf("zh-CN", "en"), AppLanguage.entries.map { it.tag }.toSet())
    }

    private fun strings(directory: String): Map<String, String> {
        val file = File("src/main/res/$directory/strings.xml")
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val nodes = document.getElementsByTagName("string")
        return (0 until nodes.length).associate { index ->
            val node = nodes.item(index)
            node.attributes.getNamedItem("name").nodeValue to node.textContent.replace("\\'", "'")
        }
    }

    @Test fun eachLanguageHasEveryResourceAndEquivalentFormatArguments() {
        val english = strings("values")
        val chinese = strings("values-zh-rCN")
        assertTrue("Resources are unexpectedly missing", english.size > 250)
        assertEquals(english.keys, chinese.keys)
        val argument = Regex("%[0-9]+\\$[ds]")
        english.forEach { (key, text) ->
            assertEquals(key, argument.findAll(text).map { it.value }.sorted().toList(),
                argument.findAll(chinese.getValue(key)).map { it.value }.sorted().toList())
        }
    }

    @Test fun chineseStaticCopyContainsNoUntranslatedEnglishWords() {
        strings("values-zh-rCN").forEach { (key, text) ->
            // Brand, formatted arguments and the exchange-file extension are intentional identifiers.
            val copy = text.replace("Together", "").replace(Regex("%[0-9]+\\$[ds]"), "")
                .replace(".json", "")
            assertFalse("Untranslated copy at $key: $text", Regex("[A-Za-z]").containsMatchIn(copy))
        }
    }

    @Test fun englishStaticCopyContainsNoChineseAndSavedGiftDoesNotClaimDelivery() {
        val english = strings("values")
        english.forEach { (key, text) ->
            assertFalse("Untranslated copy at $key", Regex("[\\u4e00-\\u9fff]").containsMatchIn(text))
        }
        assertTrue(english.getValue("gift_quota_used").contains("saved"))
        assertFalse(english.getValue("gift_quota_used").contains("delivered", ignoreCase = true))
        assertTrue(english.getValue("gift_title_boy_text").contains("boyfriend"))
        assertTrue(english.getValue("gift_title_girl_text").contains("girlfriend"))
    }
}
