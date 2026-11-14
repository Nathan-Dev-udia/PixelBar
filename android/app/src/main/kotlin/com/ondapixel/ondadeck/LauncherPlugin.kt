package com.ondapixel.ondadeck

import android.app.Activity
import android.app.ActivityManager
import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.ArrayDeque
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Minimal Kotlin bridge behind `MethodChannel("com.ondapixel.ondadeck/launcher")`.
 *
 * All PackageManager queries, icon rendering, SAF tree scans and image downsampling
 * run on a background [ExecutorService] so the Android main thread never stalls.
 */
class LauncherPlugin(
    private val activity: Activity,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.ondapixel.ondadeck/launcher"
        private const val REQ_PICK_DIRECTORY = 4101
        private const val REQ_PICK_FILE = 4102
        private const val REQ_INSTALL_PERMISSION = 4103
        private const val MAX_TEXT_BYTES = 2 * 1024 * 1024
        private const val MAX_ARCHIVE_BYTES = 64L * 1024L * 1024L
    }

    private var channel: MethodChannel? = null
    private val executor: ExecutorService = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPickerResult: MethodChannel.Result? = null
    private var pendingPickerIsTree: Boolean = false
    private var pendingInstallResult: MethodChannel.Result? = null
    private var pendingInstallApkPath: String? = null

    fun attach(messenger: BinaryMessenger) {
        val ch = MethodChannel(messenger, CHANNEL_NAME)
        ch.setMethodCallHandler(this)
        channel = ch
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        pendingPickerResult?.error("CANCELLED", "Activity detached.", null)
        pendingPickerResult = null
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInstalledApps" -> {
                val gamesOnly = call.argument<Boolean>("gamesOnly") ?: false
                runAsync(result) { getInstalledApps(gamesOnly) }
            }
            "getAppIcons" -> {
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                val sizePx = (call.argument<Int>("sizePx") ?: 192).coerceIn(32, 512)
                runAsync(result) { getAppIcons(packages, sizePx) }
            }
            "isPackageInstalled" -> {
                val pkg = call.argument<String>("packageName")
                if (pkg.isNullOrBlank()) {
                    result.success(false)
                } else {
                    runAsync(result) { getPackageInfoCompat(pkg) != null }
                }
            }
            "launchTarget" -> launchTarget(call, result)
            "pickDirectory" -> startDirectoryPicker(call, result)
            "pickFile" -> startFilePicker(call, result)
            "getPersistedUris" -> runAsync(result) { getPersistedUris() }
            "releasePersistedUri" -> {
                val uri = call.argument<String>("uri")
                if (uri.isNullOrBlank()) {
                    result.success(null)
                } else {
                    runAsync(result) {
                        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        try {
                            activity.contentResolver.releasePersistableUriPermission(Uri.parse(uri), flags)
                        } catch (_: SecurityException) {
                            // Ignore if already revoked.
                        }
                        null
                    }
                }
            }
            "listDirectory" -> {
                val treeUri = call.argument<String>("treeUri")
                if (treeUri.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "treeUri is required.", null)
                } else {
                    val recursive = call.argument<Boolean>("recursive") ?: false
                    val extensions = call.argument<List<String>>("extensions")
                        ?.map { it.lowercase() }
                        ?.toSet()
                    val maxDepth = (call.argument<Int>("maxDepth") ?: 6).coerceIn(1, 16)
                    val limit = (call.argument<Int>("limit") ?: 20000).coerceIn(1, 50000)
                    runAsync(result) { listDirectory(treeUri, recursive, extensions, maxDepth, limit) }
                }
            }
            "importArtwork" -> {
                val uri = call.argument<String>("uri")
                val maxWidth = (call.argument<Int>("maxWidth") ?: 512).coerceIn(32, 2048)
                val maxHeight = (call.argument<Int>("maxHeight") ?: 512).coerceIn(32, 2048)
                if (uri.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "uri is required.", null)
                } else {
                    runAsync(result) { importArtwork(uri, maxWidth, maxHeight) }
                }
            }
            "readText" -> {
                val uri = call.argument<String>("uri")
                if (uri.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "uri is required.", null)
                } else {
                    runAsync(result) { readText(uri) }
                }
            }
            "copyDocumentToCache" -> {
                val uri = call.argument<String>("uri")
                val preferredName = call.argument<String>("preferredName")
                if (uri.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "uri is required.", null)
                } else {
                    runAsync(result) { copyDocumentToCache(uri, preferredName) }
                }
            }
            "getDeviceProfile" -> runAsync(result) { getDeviceProfile() }
            "installApk" -> {
                val filePath = call.argument<String>("filePath")
                if (filePath.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "filePath is required.", null)
                } else {
                    installApk(filePath, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQ_INSTALL_PERMISSION) {
            val pendingResult = pendingInstallResult ?: return true
            val apkPath = pendingInstallApkPath
            pendingInstallResult = null
            pendingInstallApkPath = null
            if (apkPath.isNullOrBlank()) {
                pendingResult.success(false)
                return true
            }
            val canInstall = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                activity.packageManager.canRequestPackageInstalls()
            if (!canInstall) {
                pendingResult.success(false)
                return true
            }
            runAsync(pendingResult) { launchApkInstallerIntent(apkPath) }
            return true
        }
        if (requestCode != REQ_PICK_DIRECTORY && requestCode != REQ_PICK_FILE) return false
        val result = pendingPickerResult ?: return true
        val isTree = pendingPickerIsTree
        pendingPickerResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }

        val uri = data.data!!
        val takeFlags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        runAsync(result) {
            val persisted = try {
                val persistFlags = if (takeFlags == 0) Intent.FLAG_GRANT_READ_URI_PERMISSION else takeFlags
                activity.contentResolver.takePersistableUriPermission(uri, persistFlags)
                true
            } catch (_: SecurityException) {
                false
            }
            buildSafEntry(uri, isTree, persisted)
        }
        return true
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (t: Throwable) {
                mainHandler.post { result.error("NATIVE_ERROR", t.message ?: t.javaClass.simpleName, null) }
            }
        }
    }

    // ---- PackageManager ----------------------------------------------------------

    private fun getInstalledApps(gamesOnly: Boolean): List<Map<String, Any?>> {
        val pm = activity.packageManager
        val selfPackage = activity.packageName
        val launcherPackages = queryLauncherPackages(pm, Intent.CATEGORY_LAUNCHER)
        val leanbackPackages = queryLauncherPackages(pm, Intent.CATEGORY_LEANBACK_LAUNCHER)
        val allPackages = (launcherPackages + leanbackPackages) - selfPackage

        val results = ArrayList<Map<String, Any?>>(allPackages.size)
        for (pkg in allPackages) {
            val pkgInfo = getPackageInfoCompat(pkg) ?: continue
            val appInfo = pkgInfo.applicationInfo ?: continue
            val isGame = isGameApplication(appInfo)
            if (gamesOnly && !isGame) continue

            val isSystem = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
            val label = pm.getApplicationLabel(appInfo).toString().ifBlank { pkg }

            results.add(
                mapOf(
                    "packageName" to pkg,
                    "label" to label,
                    "isGame" to isGame,
                    "isSystem" to isSystem,
                    "isLeanback" to leanbackPackages.contains(pkg),
                    "versionName" to pkgInfo.versionName,
                    "firstInstallTime" to pkgInfo.firstInstallTime,
                    "lastUpdateTime" to pkgInfo.lastUpdateTime,
                )
            )
        }
        results.sortBy { (it["label"] as? String)?.lowercase() ?: "" }
        return results
    }

    private fun queryLauncherPackages(pm: PackageManager, category: String): Set<String> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(category)
        val flags = PackageManager.MATCH_ALL
        val resolved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(flags.toLong()))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, flags)
        }
        return resolved.mapNotNull { it.activityInfo?.packageName }.toSet()
    }

    private fun isGameApplication(appInfo: ApplicationInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && appInfo.category == ApplicationInfo.CATEGORY_GAME) {
            return true
        }
        @Suppress("DEPRECATION")
        return (appInfo.flags and ApplicationInfo.FLAG_IS_GAME) != 0
    }

    private fun getAppIcons(packages: List<String>, sizePx: Int): Map<String, String> {
        val pm = activity.packageManager
        val dir = File(activity.filesDir, "icons").apply { mkdirs() }
        val out = HashMap<String, String>(packages.size)

        for (pkg in packages) {
            val pkgInfo = getPackageInfoCompat(pkg) ?: continue
            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                pkgInfo.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                pkgInfo.versionCode.toLong()
            }
            val safePkg = pkg.replace(Regex("[^A-Za-z0-9._-]"), "_")
            val file = File(dir, "${safePkg}_${versionCode}_${sizePx}.png")
            if (file.exists() && file.length() > 0L) {
                out[pkg] = file.absolutePath
                continue
            }

            try {
                val drawable = pm.getApplicationIcon(pkg)
                val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
                try {
                    val canvas = Canvas(bitmap)
                    drawable.setBounds(0, 0, sizePx, sizePx)
                    drawable.draw(canvas)
                    FileOutputStream(file).use { stream ->
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                    }
                    out[pkg] = file.absolutePath
                } finally {
                    bitmap.recycle()
                }
            } catch (_: Throwable) {
                // Skip packages whose icons fail to load.
            }
        }
        return out
    }

    private fun getPackageInfoCompat(packageName: String): PackageInfo? {
        val pm = activity.packageManager
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0L))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(packageName, 0)
            }
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }

    // ---- Universal Launcher ------------------------------------------------------

    private fun launchTarget(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("INVALID_CONFIG", "Launch payload must be a map.", null)
            return
        }

        val type = args["type"] as? String
        val packageName = args["packageName"] as? String
        val activityName = args["activityName"] as? String
        val action = args["action"] as? String
        val dataUri = args["dataUri"] as? String
        val mimeType = args["mimeType"] as? String
        val categories = (args["categories"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList()
        val extras = args["extras"] as? Map<*, *> ?: emptyMap<Any?, Any?>()
        val flagNames = (args["flags"] as? List<*>)?.mapNotNull { it as? String } ?: listOf("NEW_TASK")
        val grantRead = args["grantUriRead"] as? Boolean ?: true
        val grantWrite = args["grantUriWrite"] as? Boolean ?: false

        val isApkIntent = type == "intent" && (
            mimeType == "application/vnd.android.package-archive" ||
                (dataUri?.lowercase()?.endsWith(".apk") == true)
            )
        if (!isApkIntent && !packageName.isNullOrBlank() && getPackageInfoCompat(packageName) == null) {
            result.error("NOT_INSTALLED", "Package not installed: $packageName", null)
            return
        }

        val intent: Intent = when (type) {
            "package" -> {
                if (packageName.isNullOrBlank()) {
                    result.error("INVALID_CONFIG", "packageName is required for package launch.", null)
                    return
                }
                if (!activityName.isNullOrBlank()) {
                    Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_LAUNCHER)
                        component = ComponentName(packageName, resolveActivityName(packageName, activityName))
                    }
                } else {
                    val pm = activity.packageManager
                    pm.getLaunchIntentForPackage(packageName)
                        ?: pm.getLeanbackLaunchIntentForPackage(packageName)
                        ?: run {
                            result.error("ACTIVITY_NOT_FOUND", "No launcher activity found for $packageName", null)
                            return
                        }
                }
            }
            "intent" -> {
                val installedApkPkg = if (isApkIntent) {
                    if (!packageName.isNullOrBlank() && getPackageInfoCompat(packageName) != null) {
                        packageName
                    } else if (!dataUri.isNullOrBlank()) {
                        resolveInstalledPackageFromApkUri(Uri.parse(dataUri))
                    } else {
                        null
                    }
                } else {
                    null
                }
                val installedLaunchIntent = installedApkPkg?.let { pkg ->
                    val pm = activity.packageManager
                    pm.getLaunchIntentForPackage(pkg) ?: pm.getLeanbackLaunchIntentForPackage(pkg)
                }
                if (installedLaunchIntent != null) {
                    installedLaunchIntent
                } else {
                    val built = Intent(action ?: Intent.ACTION_VIEW)
                    val parsedUri = dataUri?.takeIf { it.isNotBlank() }?.let { Uri.parse(it) }
                    val effectiveMime = if (isApkIntent) "application/vnd.android.package-archive" else mimeType
                    when {
                        parsedUri != null && !effectiveMime.isNullOrBlank() -> built.setDataAndType(parsedUri, effectiveMime)
                        parsedUri != null -> built.data = parsedUri
                        !effectiveMime.isNullOrBlank() -> built.type = effectiveMime
                    }
                    if (!isApkIntent && !packageName.isNullOrBlank()) {
                        if (!activityName.isNullOrBlank()) {
                            built.component = ComponentName(packageName, resolveActivityName(packageName, activityName))
                        } else {
                            built.`package` = packageName
                        }
                    }
                    for (cat in categories) {
                        built.addCategory(cat)
                    }
                    applyExtras(built, extras)
                    if (parsedUri != null && parsedUri.scheme == "content" && (grantRead || grantWrite || isApkIntent)) {
                        built.clipData = ClipData.newRawUri(null, parsedUri)
                        if (grantRead || isApkIntent) built.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        if (grantWrite) built.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    }
                    built
                }
            }
            else -> {
                result.error("INVALID_CONFIG", "Unknown launch type: $type", null)
                return
            }
        }

        for (flag in flagNames) {
            mapLaunchFlag(flag)?.let { intent.addFlags(it) }
        }

        try {
            activity.startActivity(intent)
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("ACTIVITY_NOT_FOUND", e.message ?: "Target activity not found.", null)
        } catch (e: SecurityException) {
            result.error("SECURITY", e.message ?: "Permission denied launching target.", null)
        } catch (e: IllegalArgumentException) {
            result.error("INVALID_CONFIG", e.message ?: "Invalid launch configuration.", null)
        }
    }

    private fun resolveActivityName(packageName: String, activityName: String): String =
        if (activityName.startsWith(".")) "$packageName$activityName" else activityName

    private fun mapLaunchFlag(flag: String): Int? = when (flag) {
        "NEW_TASK" -> Intent.FLAG_ACTIVITY_NEW_TASK
        "CLEAR_TASK" -> Intent.FLAG_ACTIVITY_CLEAR_TASK
        "CLEAR_TOP" -> Intent.FLAG_ACTIVITY_CLEAR_TOP
        "SINGLE_TOP" -> Intent.FLAG_ACTIVITY_SINGLE_TOP
        "NO_HISTORY" -> Intent.FLAG_ACTIVITY_NO_HISTORY
        "RESET_TASK_IF_NEEDED" -> Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        "NO_ANIMATION" -> Intent.FLAG_ACTIVITY_NO_ANIMATION
        "EXCLUDE_FROM_RECENTS" -> Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
        "MULTIPLE_TASK" -> Intent.FLAG_ACTIVITY_MULTIPLE_TASK
        else -> null
    }

    private fun applyExtras(intent: Intent, extras: Map<*, *>) {
        for ((k, raw) in extras) {
            val key = k as? String ?: continue
            val spec = raw as? Map<*, *> ?: continue
            val type = spec["type"] as? String ?: continue
            val value = spec["value"] ?: continue
            when (type) {
                "string" -> if (value is String) intent.putExtra(key, value)
                "int" -> if (value is Number) intent.putExtra(key, value.toInt())
                "long" -> if (value is Number) intent.putExtra(key, value.toLong())
                "float" -> if (value is Number) intent.putExtra(key, value.toFloat())
                "double" -> if (value is Number) intent.putExtra(key, value.toDouble())
                "bool" -> if (value is Boolean) intent.putExtra(key, value)
                "uri" -> if (value is String) intent.putExtra(key, Uri.parse(value))
                "stringList" -> if (value is List<*>) {
                    intent.putStringArrayListExtra(key, ArrayList(value.map { it.toString() }))
                }
                "stringArray" -> if (value is List<*>) {
                    intent.putExtra(key, value.map { it.toString() }.toTypedArray())
                }
            }
        }
    }

    // ---- Storage Access Framework (SAF) ------------------------------------------

    private fun startDirectoryPicker(call: MethodCall, result: MethodChannel.Result) {
        if (pendingPickerResult != null) {
            result.error("PICKER_BUSY", "A document picker is already open.", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            val initialUri = call.argument<String>("initialUri")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !initialUri.isNullOrBlank()) {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(initialUri))
            }
        }
        pendingPickerResult = result
        pendingPickerIsTree = true
        activity.startActivityForResult(intent, REQ_PICK_DIRECTORY)
    }

    private fun startFilePicker(call: MethodCall, result: MethodChannel.Result) {
        if (pendingPickerResult != null) {
            result.error("PICKER_BUSY", "A document picker is already open.", null)
            return
        }
        val mimeTypes = call.argument<List<String>>("mimeTypes") ?: listOf("*/*")
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = if (mimeTypes.size == 1) mimeTypes.first() else "*/*"
            if (mimeTypes.size > 1) {
                putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
            }
            addFlags(
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        }
        pendingPickerResult = result
        pendingPickerIsTree = false
        activity.startActivityForResult(intent, REQ_PICK_FILE)
    }

    private fun buildSafEntry(uri: Uri, isTree: Boolean, persisted: Boolean): Map<String, Any?> {
        var name = uri.lastPathSegment ?: uri.toString()
        var mimeType: String? = null
        var size: Long? = null
        var lastModified: Long? = null

        val queryUri = if (isTree) {
            val docId = DocumentsContract.getTreeDocumentId(uri)
            DocumentsContract.buildDocumentUriUsingTree(uri, docId)
        } else {
            uri
        }

        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        try {
            activity.contentResolver.query(queryUri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                    val mimeIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                    val sizeIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                    val modIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                    if (nameIdx >= 0 && !cursor.isNull(nameIdx)) name = cursor.getString(nameIdx)
                    if (mimeIdx >= 0 && !cursor.isNull(mimeIdx)) mimeType = cursor.getString(mimeIdx)
                    if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) size = cursor.getLong(sizeIdx)
                    if (modIdx >= 0 && !cursor.isNull(modIdx)) lastModified = cursor.getLong(modIdx)
                }
            }
        } catch (_: Throwable) {
            if (!isTree) {
                activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
                    if (c.moveToFirst()) {
                        val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        val s = c.getColumnIndex(OpenableColumns.SIZE)
                        if (n >= 0 && !c.isNull(n)) name = c.getString(n)
                        if (s >= 0 && !c.isNull(s)) size = c.getLong(s)
                    }
                }
            }
        }

        val isDir = isTree || mimeType == DocumentsContract.Document.MIME_TYPE_DIR
        return mapOf(
            "uri" to uri.toString(),
            "name" to name,
            "isDirectory" to isDir,
            "mimeType" to mimeType,
            "size" to size,
            "lastModified" to lastModified,
            "persisted" to persisted,
        )
    }

    private fun getPersistedUris(): List<Map<String, Any?>> =
        activity.contentResolver.persistedUriPermissions.map { perm ->
            mapOf(
                "uri" to perm.uri.toString(),
                "read" to perm.isReadPermission,
                "write" to perm.isWritePermission,
                "persistedTime" to perm.persistedTime,
            )
        }

    private fun listDirectory(
        treeUriString: String,
        recursive: Boolean,
        extensions: Set<String>?,
        maxDepth: Int,
        limit: Int,
    ): List<Map<String, Any?>> {
        val treeUri = Uri.parse(treeUriString)
        val rootDocId = DocumentsContract.getTreeDocumentId(treeUri)
        val queue = ArrayDeque<Pair<String, Int>>()
        queue.add(rootDocId to 0)

        val entries = ArrayList<Map<String, Any?>>()
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )

        while (queue.isNotEmpty() && entries.size < limit) {
            val (parentDocId, depth) = queue.removeFirst()
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
            activity.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                val idIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mimeIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                val sizeIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                val modIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)

                while (cursor.moveToNext() && entries.size < limit) {
                    val docId = if (idIdx >= 0) cursor.getString(idIdx) else continue
                    val name = if (nameIdx >= 0 && !cursor.isNull(nameIdx)) cursor.getString(nameIdx) else docId
                    val mime = if (mimeIdx >= 0 && !cursor.isNull(mimeIdx)) cursor.getString(mimeIdx) else null
                    val size = if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) cursor.getLong(sizeIdx) else null
                    val mod = if (modIdx >= 0 && !cursor.isNull(modIdx)) cursor.getLong(modIdx) else null
                    val isDir = mime == DocumentsContract.Document.MIME_TYPE_DIR

                    if (isDir) {
                        if (recursive && depth + 1 < maxDepth) {
                            queue.add(docId to depth + 1)
                        } else if (!recursive) {
                            val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                            entries.add(
                                mapOf(
                                    "uri" to docUri.toString(),
                                    "name" to name,
                                    "isDirectory" to true,
                                    "mimeType" to mime,
                                    "size" to size,
                                    "lastModified" to mod,
                                    "persisted" to true,
                                )
                            )
                        }
                        continue
                    }

                    if (extensions != null) {
                        val dot = name.lastIndexOf('.')
                        val ext = if (dot >= 0) name.substring(dot + 1).lowercase() else ""
                        if (!extensions.contains(ext)) continue
                    }

                    val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                    val dotIdx = name.lastIndexOf('.')
                    val fileExt = if (dotIdx >= 0) name.substring(dotIdx + 1).lowercase() else ""
                    val apkMeta = if (fileExt == "apk") {
                        inspectApkDocument(docUri, docId, name)
                    } else {
                        null
                    }
                    val entryMap = HashMap<String, Any?>(11).apply {
                        put("uri", docUri.toString())
                        put("name", name)
                        put("isDirectory", false)
                        put("mimeType", mime)
                        put("size", size)
                        put("lastModified", mod)
                        put("persisted", true)
                        if (apkMeta != null) {
                            putAll(apkMeta)
                        }
                    }
                    entries.add(entryMap)
                }
            }
        }
        return entries
    }

    private fun getArchivePackageInfoCompat(archivePath: String): PackageInfo? {
        val pm = activity.packageManager
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageArchiveInfo(archivePath, PackageManager.PackageInfoFlags.of(0L))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageArchiveInfo(archivePath, 0)
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun inspectApkDocument(docUri: Uri, docId: String, fileName: String): Map<String, Any?> {
        val pm = activity.packageManager
        var pkgName: String? = null
        var label: String? = null
        var iconPath: String? = null

        try {
            activity.contentResolver.openFileDescriptor(docUri, "r")?.use { pfd ->
                val fdPath = "/proc/self/fd/${pfd.fd}"
                val info = getArchivePackageInfoCompat(fdPath)
                if (info != null) {
                    pkgName = info.packageName
                    val appInfo = info.applicationInfo
                    if (appInfo != null) {
                        appInfo.sourceDir = fdPath
                        appInfo.publicSourceDir = fdPath
                        label = appInfo.loadLabel(pm).toString().takeIf { it.isNotBlank() }
                        iconPath = renderDrawableToIconFile(
                            appInfo.loadIcon(pm),
                            "apk_${sha256(pkgName ?: docUri.toString())}_192.png",
                            192,
                        )
                    }
                }
            }
        } catch (_: Throwable) {
            // Fall through to path-based fallback.
        }

        if (pkgName == null && docId.startsWith("primary:")) {
            val rawPath = "/storage/emulated/0/${docId.substringAfter("primary:")}"
            try {
                if (File(rawPath).canRead()) {
                    val info = getArchivePackageInfoCompat(rawPath)
                    if (info != null) {
                        pkgName = info.packageName
                        val appInfo = info.applicationInfo
                        if (appInfo != null) {
                            appInfo.sourceDir = rawPath
                            appInfo.publicSourceDir = rawPath
                            label = label ?: appInfo.loadLabel(pm).toString().takeIf { it.isNotBlank() }
                            if (iconPath == null) {
                                iconPath = renderDrawableToIconFile(
                                    appInfo.loadIcon(pm),
                                    "apk_${sha256(pkgName ?: docUri.toString())}_192.png",
                                    192,
                                )
                            }
                        }
                    }
                }
            } catch (_: Throwable) {
                // Ignore inaccessible direct storage paths.
            }
        }

        val resolvedPkg = pkgName
        val installed = if (resolvedPkg != null && getPackageInfoCompat(resolvedPkg) != null) {
            if (iconPath == null) {
                iconPath = getAppIcons(listOf(resolvedPkg), 192)[resolvedPkg]
            }
            if (label == null) {
                val installedInfo = getPackageInfoCompat(resolvedPkg)?.applicationInfo
                if (installedInfo != null) {
                    label = pm.getApplicationLabel(installedInfo).toString().takeIf { it.isNotBlank() }
                }
            }
            true
        } else {
            false
        }

        val fallbackLabel = fileName.substringBeforeLast('.').ifBlank { fileName }
        return mapOf(
            "apkPackageName" to pkgName,
            "apkLabel" to (label ?: fallbackLabel),
            "apkIconPath" to iconPath,
            "apkInstalled" to installed,
        )
    }

    private fun resolveInstalledPackageFromApkUri(uri: Uri): String? {
        try {
            activity.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                val pkg = getArchivePackageInfoCompat("/proc/self/fd/${pfd.fd}")?.packageName
                if (!pkg.isNullOrBlank() && getPackageInfoCompat(pkg) != null) {
                    return pkg
                }
            }
        } catch (_: Throwable) {
            // Try document path fallback below.
        }
        try {
            if (DocumentsContract.isDocumentUri(activity, uri)) {
                val docId = DocumentsContract.getDocumentId(uri)
                if (docId.startsWith("primary:")) {
                    val rawPath = "/storage/emulated/0/${docId.substringAfter("primary:")}"
                    val pkg = getArchivePackageInfoCompat(rawPath)?.packageName
                    if (!pkg.isNullOrBlank() && getPackageInfoCompat(pkg) != null) {
                        return pkg
                    }
                }
            }
        } catch (_: Throwable) {
            // Ignore.
        }
        return null
    }

    private fun renderDrawableToIconFile(drawable: Drawable?, fileName: String, sizePx: Int): String? {
        if (drawable == null) return null
        val dir = File(activity.filesDir, "icons").apply { mkdirs() }
        val file = File(dir, fileName)
        if (file.exists() && file.length() > 0L) {
            return file.absolutePath
        }
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        return try {
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, sizePx, sizePx)
            drawable.draw(canvas)
            FileOutputStream(file).use { stream ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            }
            file.absolutePath
        } catch (_: Throwable) {
            null
        } finally {
            bitmap.recycle()
        }
    }

    private fun importArtwork(uriString: String, maxWidth: Int, maxHeight: Int): String {
        val hash = sha256("${uriString}_${maxWidth}x${maxHeight}")
        val dir = File(activity.filesDir, "artwork").apply { mkdirs() }
        val outFile = File(dir, "$hash.webp")
        if (outFile.exists() && outFile.length() > 0L) {
            return outFile.absolutePath
        }

        val uri = Uri.parse(uriString)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        activity.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, bounds)
        } ?: throw IllegalStateException("Cannot open artwork stream: $uriString")

        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw IllegalArgumentException("Invalid image bounds for $uriString")
        }

        val decodeOpts = BitmapFactory.Options().apply {
            inSampleSize = calculateInSampleSize(bounds.outWidth, bounds.outHeight, maxWidth, maxHeight)
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = activity.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, decodeOpts)
        } ?: throw IllegalStateException("Failed to decode artwork: $uriString")

        val scaled = try {
            val ratio = minOf(maxWidth.toFloat() / decoded.width, maxHeight.toFloat() / decoded.height, 1f)
            if (ratio < 1f) {
                val targetW = max(1, (decoded.width * ratio).roundToInt())
                val targetH = max(1, (decoded.height * ratio).roundToInt())
                Bitmap.createScaledBitmap(decoded, targetW, targetH, true).also {
                    if (it !== decoded) decoded.recycle()
                }
            } else {
                decoded
            }
        } catch (t: Throwable) {
            decoded.recycle()
            throw t
        }

        try {
            val format = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Bitmap.CompressFormat.WEBP_LOSSY
            } else {
                @Suppress("DEPRECATION")
                Bitmap.CompressFormat.WEBP
            }
            FileOutputStream(outFile).use { stream ->
                scaled.compress(format, 85, stream)
            }
        } finally {
            scaled.recycle()
        }
        return outFile.absolutePath
    }

    private fun calculateInSampleSize(srcWidth: Int, srcHeight: Int, reqWidth: Int, reqHeight: Int): Int {
        var inSampleSize = 1
        while ((srcHeight / (inSampleSize * 2)) >= reqHeight && (srcWidth / (inSampleSize * 2)) >= reqWidth) {
            inSampleSize *= 2
        }
        return inSampleSize
    }

    private fun readText(uriString: String): String {
        val uri = Uri.parse(uriString)
        val buffer = ByteArrayOutputStream()
        val chunk = ByteArray(8192)
        var total = 0
        activity.contentResolver.openInputStream(uri)?.use { input ->
            while (true) {
                val read = input.read(chunk)
                if (read <= 0) break
                total += read
                if (total > MAX_TEXT_BYTES) {
                    throw IllegalArgumentException("Text document exceeds 2 MB limit.")
                }
                buffer.write(chunk, 0, read)
            }
        } ?: throw IllegalStateException("Cannot open text stream: $uriString")
        return buffer.toString(Charsets.UTF_8.name())
    }

    private fun copyDocumentToCache(uriString: String, preferredName: String?): String {
        val uri = Uri.parse(uriString)
        val rawName = preferredName?.takeIf { it.isNotBlank() } ?: "theme_import.ondatheme"
        val safeName = rawName.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val dir = File(activity.cacheDir, "theme_imports").apply { mkdirs() }
        val outFile = File(dir, "${System.currentTimeMillis()}_$safeName")

        val chunk = ByteArray(16384)
        var total = 0L
        activity.contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(outFile).use { output ->
                while (true) {
                    val read = input.read(chunk)
                    if (read <= 0) break
                    total += read
                    if (total > MAX_ARCHIVE_BYTES) {
                        outFile.delete()
                        throw IllegalArgumentException("Theme archive exceeds 64 MB limit.")
                    }
                    output.write(chunk, 0, read)
                }
            }
        } ?: throw IllegalStateException("Cannot open document stream: $uriString")

        return outFile.absolutePath
    }

    // ---- Hardware Profile --------------------------------------------------------

    private fun getDeviceProfile(): Map<String, Any?> {
        val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        am.getMemoryInfo(memInfo)

        val uiModeManager = activity.getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        val isTv = uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION

        return mapOf(
            "sdkInt" to Build.VERSION.SDK_INT,
            "totalRamBytes" to memInfo.totalMem,
            "isLowRamDevice" to am.isLowRamDevice,
            "memoryClassMb" to am.memoryClass,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "isTelevision" to isTv,
        )
    }

    private fun installApk(filePath: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            pendingInstallResult?.success(false)
            pendingInstallResult = result
            pendingInstallApkPath = filePath
            try {
                val settingsIntent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${activity.packageName}"),
                )
                activity.startActivityForResult(settingsIntent, REQ_INSTALL_PERMISSION)
            } catch (t: Throwable) {
                pendingInstallResult = null
                pendingInstallApkPath = null
                result.error(
                    "INSTALL_PERMISSION_ERROR",
                    t.message ?: "Unable to open unknown app sources settings.",
                    null,
                )
            }
            return
        }
        runAsync(result) { launchApkInstallerIntent(filePath) }
    }

    private fun launchApkInstallerIntent(filePath: String): Boolean {
        val source = File(filePath)
        if (!source.exists() || !source.isFile) {
            throw IllegalArgumentException("APK file not found: $filePath")
        }
        val cacheDir = activity.cacheDir.canonicalFile
        val filesDir = activity.filesDir.canonicalFile
        val canonicalSource = source.canonicalFile
        val shareableFile = if (
            canonicalSource.path.startsWith(cacheDir.path + File.separator) ||
            canonicalSource.path.startsWith(filesDir.path + File.separator)
        ) {
            canonicalSource
        } else {
            val updatesDir = File(cacheDir, "updates")
            if (!updatesDir.exists()) updatesDir.mkdirs()
            val staged = File(updatesDir, canonicalSource.name.ifBlank { "ondadeck_update.apk" })
            canonicalSource.copyTo(staged, overwrite = true)
            staged
        }

        val authority = "${activity.packageName}.fileprovider"
        val contentUri = FileProvider.getUriForFile(activity, authority, shareableFile)
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri, "application/vnd.android.package-archive")
            clipData = ClipData.newRawUri("APK Update", contentUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
        }
        mainHandler.post {
            activity.startActivity(installIntent)
        }
        return true
    }

    private fun sha256(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }
}
