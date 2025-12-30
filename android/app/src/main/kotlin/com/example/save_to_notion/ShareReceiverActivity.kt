package com.example.save_to_notion

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject
import java.io.File

class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Thread {
            try {
                handleIntent(intent)
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                finish()
            }
        }.start()
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_SEND) return

        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT) ?: intent.clipData?.getItemAt(0)?.coerceToText(this)?.toString()
        if (sharedText == null) return

        // read token and db from SharedPreferences (written by Flutter)
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        var token = prefs.getString("notion_token", null)
        var dbId = prefs.getString("notion_db_id", null)

        // Flutter's shared_preferences stores keys with a "flutter." prefix in the XML
        // try those variants if plain keys are not present
        if (token == null) token = prefs.getString("flutter.notion_token", null)
        if (dbId == null) dbId = prefs.getString("flutter.notion_db_id", null)

        if (token == null || dbId == null) {
            // older/shared prefs name maybe different
            val prefs2 = getSharedPreferences("flutter.", MODE_PRIVATE)
            if (token == null) token = prefs2.getString("notion_token", null)
            if (dbId == null) dbId = prefs2.getString("notion_db_id", null)
            // also try flutter-prefixed keys in prefs2
            if (token == null) token = prefs2.getString("flutter.notion_token", null)
            if (dbId == null) dbId = prefs2.getString("flutter.notion_db_id", null)
        }

        if (token == null || dbId == null) {
            // Debug: log available keys in FlutterSharedPreferences to help diagnose missing values
            try {
                val all = prefs.all
                val keys = all.keys.joinToString(", ")
                android.util.Log.i("ShareReceiver", "FlutterSharedPreferences keys: $keys")
                // Also enumerate all shared_prefs files and log their contents
                try {
                    val dir = File(applicationInfo.dataDir, "shared_prefs")
                    if (dir.exists() && dir.isDirectory) {
                        val files = dir.listFiles()
                        if (files != null) {
                            for (f in files) {
                                try {
                                    val name = f.name.removeSuffix(".xml")
                                    val p = getSharedPreferences(name, MODE_PRIVATE)
                                    val map = p.all
                                    android.util.Log.i("ShareReceiver", "prefs file: $name -> keys=${map.keys}")
                                } catch (e: Exception) { e.printStackTrace() }
                            }
                        }
                    }
                } catch (e: Exception) { e.printStackTrace() }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            runOnUiThread { Toast.makeText(this, "Notion token/DB not set", Toast.LENGTH_SHORT).show() }
            return
        }

        val url = extractUrl(sharedText)
        var title = sharedText
        if (url != null) title = title.replace(url, "").trim()
        if (title.isEmpty() && url != null) {
            val fetched = fetchTitle(url)
            if (fetched != null) title = fetched
        }

        // Fetch DB properties to map keys
        val props = fetchDatabaseProperties(dbId, token)
        val titleProp = props.entries.firstOrNull { it.value == "title" }?.key ?: props.keys.firstOrNull { it.lowercase().contains("name") } ?: "Name"
        val urlProp = props.entries.firstOrNull { it.value == "url" }?.key ?: props.keys.firstOrNull { it.lowercase().contains("url") || it.lowercase().contains("link") } ?: "URL"

        val payload = JSONObject()
        val parent = JSONObject()
        parent.put("database_id", dbId)
        payload.put("parent", parent)

        val properties = JSONObject()
        val titleObj = JSONObject()
        val titleArr = org.json.JSONArray()
        val titleText = JSONObject()
        titleText.put("text", JSONObject().put("content", title))
        titleArr.put(titleText)
        titleObj.put("title", titleArr)
        properties.put(titleProp, titleObj)

        val urlObj = JSONObject()
        urlObj.put("url", url)
        properties.put(urlProp, urlObj)

        payload.put("properties", properties)

        val created = postJson("https://api.notion.com/v1/pages", payload.toString(), token)
        if (created != null) {
            runOnUiThread { Toast.makeText(this, "Saved to Notion", Toast.LENGTH_SHORT).show() }
        } else {
            runOnUiThread { Toast.makeText(this, "Failed to save to Notion", Toast.LENGTH_SHORT).show() }
        }
    }

    private fun extractUrl(text: String): String? {
        val re = Regex("https?://[^\\s]+")
        val m = re.find(text)
        return m?.value
    }

    private fun fetchTitle(urlStr: String): String? {
        try {
            if (urlStr.contains("youtube.com") || urlStr.contains("youtu.be")) {
                val oembed = "https://www.youtube.com/oembed?url=${java.net.URLEncoder.encode(urlStr, "UTF-8")}&format=json"
                val j = getJson(oembed)
                if (j != null) return j.optString("title", null)
            }
            val j = getText(urlStr)
            if (j != null) {
                val m = Regex("<title[^>]*>([\\s\\S]*?)</title>", RegexOption.IGNORE_CASE).find(j)
                if (m != null) return android.text.Html.fromHtml(m.groupValues[1]).toString()
            }
        } catch (e: Exception) { }
        return null
    }

    private fun fetchDatabaseProperties(dbId: String, token: String): Map<String, String> {
        val url = "https://api.notion.com/v1/databases/$dbId"
        val resp = getJson(url, token)
        val map = mutableMapOf<String, String>()
        if (resp == null) return map
        val props = resp.optJSONObject("properties") ?: return map
        val keys = props.keys()
        while (keys.hasNext()) {
            val k = keys.next()
            val v = props.optJSONObject(k)
            val t = v?.optString("type") ?: "unknown"
            map[k] = t
        }
        return map
    }

    private fun getJson(urlStr: String, token: String? = null): JSONObject? {
        val s = getText(urlStr, token)
        return if (s != null) JSONObject(s) else null
    }

    private fun getText(urlStr: String, token: String? = null): String? {
        var conn: HttpURLConnection? = null
        try {
            val url = URL(urlStr)
            conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.connectTimeout = 6000
            conn.readTimeout = 6000
            if (token != null) {
                conn.setRequestProperty("Authorization", "Bearer $token")
                conn.setRequestProperty("Notion-Version", "2022-06-28")
            }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val reader = BufferedReader(InputStreamReader(stream))
            val sb = StringBuilder()
            var line: String? = reader.readLine()
            while (line != null) {
                sb.append(line).append('\n')
                line = reader.readLine()
            }
            reader.close()
            return sb.toString()
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            conn?.disconnect()
        }
        return null
    }

    private fun postJson(urlStr: String, body: String, token: String): String? {
        var conn: HttpURLConnection? = null
        try {
            val url = URL(urlStr)
            conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.setRequestProperty("Notion-Version", "2022-06-28")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            val out = conn.outputStream
            out.write(body.toByteArray(Charsets.UTF_8))
            out.flush()
            out.close()
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val reader = BufferedReader(InputStreamReader(stream))
            val sb = StringBuilder()
            var line: String? = reader.readLine()
            while (line != null) {
                sb.append(line).append('\n')
                line = reader.readLine()
            }
            reader.close()
            return sb.toString()
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            conn?.disconnect()
        }
        return null
    }
}
