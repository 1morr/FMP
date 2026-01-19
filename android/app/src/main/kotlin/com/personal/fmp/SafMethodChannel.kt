package com.personal.fmp

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * SAF (Storage Access Framework) Platform Channel Handler
 * 
 * Provides methods for Flutter to interact with Android's SAF system,
 * enabling access to user-selected directories via content:// URIs.
 */
class SafMethodChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "exists" -> handleExists(call, result)
            "getFileSize" -> handleGetFileSize(call, result)
            "readRange" -> handleReadRange(call, result)
            "createFile" -> handleCreateFile(call, result)
            "writeToFile" -> handleWriteToFile(call, result)
            "appendToFile" -> handleAppendToFile(call, result)
            "deleteFile" -> handleDeleteFile(call, result)
            "listDirectory" -> handleListDirectory(call, result)
            "hasPersistedPermission" -> handleHasPersistedPermission(call, result)
            "getDisplayName" -> handleGetDisplayName(call, result)
            else -> result.notImplemented()
        }
    }
    
    /**
     * Check if file/directory exists at given URI
     */
    private fun handleExists(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("INVALID_ARGUMENT", "uri is required", null)
            return
        }
        
        val uri = Uri.parse(uriString)
        try {
            val cursor = context.contentResolver.query(uri, null, null, null, null)
            val exists = cursor?.use { it.count > 0 } ?: false
            result.success(exists)
        } catch (e: Exception) {
            result.success(false)
        }
    }
    
    /**
     * Get file size in bytes
     */
    private fun handleGetFileSize(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("INVALID_ARGUMENT", "uri is required", null)
            return
        }
        
        val uri = Uri.parse(uriString)
        try {
            val cursor = context.contentResolver.query(
                uri, 
                arrayOf(OpenableColumns.SIZE), 
                null, null, null
            )
            cursor?.use {
                if (it.moveToFirst()) {
                    val sizeIndex = it.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIndex >= 0) {
                        result.success(it.getLong(sizeIndex))
                        return
                    }
                }
            }
            result.error("ERROR", "Cannot get file size", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    /**
     * Read a byte range from file (for streaming audio playback)
     */
    private fun handleReadRange(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        val start = call.argument<Number>("start")?.toLong()
        val length = call.argument<Number>("length")?.toInt()
        
        if (uriString == null || start == null || length == null) {
            result.error("INVALID_ARGUMENT", "uri, start, and length are required", null)
            return
        }
        
        val uri = Uri.parse(uriString)
        
        try {
            context.contentResolver.openInputStream(uri)?.use { inputStream ->
                inputStream.skip(start)
                val buffer = ByteArray(length)
                val bytesRead = inputStream.read(buffer)
                if (bytesRead > 0) {
                    result.success(if (bytesRead == length) buffer else buffer.copyOf(bytesRead))
                } else {
                    result.success(ByteArray(0))
                }
            } ?: result.error("ERROR", "Cannot open input stream", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    /**
     * Create a file in a directory (parentUri must be a tree URI)
     */
    private fun handleCreateFile(call: MethodCall, result: MethodChannel.Result) {
        val parentUriString = call.argument<String>("parentUri")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        
        if (parentUriString == null || fileName == null) {
            result.error("INVALID_ARGUMENT", "parentUri and fileName are required", null)
            return
        }
        
        val parentUri = Uri.parse(parentUriString)
        try {
            // For tree URI, we need to get the document URI first
            val parentDocUri = if (parentUriString.contains("/tree/")) {
                // Check if this is a tree URI with a document path
                if (parentUriString.contains("/document/")) {
                    parentUri
                } else {
                    // Build document URI from tree URI
                    DocumentsContract.buildDocumentUriUsingTree(
                        parentUri,
                        DocumentsContract.getTreeDocumentId(parentUri)
                    )
                }
            } else {
                parentUri
            }
            
            val fileUri = DocumentsContract.createDocument(
                context.contentResolver,
                parentDocUri,
                mimeType,
                fileName
            )
            if (fileUri != null) {
                result.success(fileUri.toString())
            } else {
                result.error("ERROR", "Failed to create file", null)
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    /**
     * Write data to file (overwrites existing content)
     */
    private fun handleWriteToFile(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        val data = call.argument<ByteArray>("data")
        
        if (uriString == null || data == null) {
            result.error("INVALID_ARGUMENT", "uri and data are required", null)
            return
        }
        
        val uri = Uri.parse(uriString)
        
        try {
            context.contentResolver.openOutputStream(uri, "wt")?.use { outputStream ->
                outputStream.write(data)
                result.success(true)
            } ?: result.error("ERROR", "Cannot open output stream", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    /**
     * Append data to file
     */
    private fun handleAppendToFile(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        val data = call.argument<ByteArray>("data")
        
        if (uriString == null || data == null) {
            result.error("INVALID_ARGUMENT", "uri and data are required", null)
            return
        }
        
        val uri = Uri.parse(uriString)
        
        try {
            context.contentResolver.openOutputStream(uri, "wa")?.use { outputStream ->
                outputStream.write(data)
                result.success(true)
            } ?: result.error("ERROR", "Cannot open output stream", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    /**
     * Delete a file or directory
     */
    private fun handleDeleteFile(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("INVALID_ARGUMENT", "uri is required", null)
            return
        }
        
        val uri = Uri.parse(uriString)
        
        try {
            val deleted = DocumentsContract.deleteDocument(context.contentResolver, uri)
            result.success(deleted)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    /**
     * List contents of a directory (tree URI)
     */
    private fun handleListDirectory(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("INVALID_ARGUMENT", "uri is required", null)
            return
        }
        
        val treeUri = Uri.parse(uriString)
        
        try {
            val docId = if (uriString.contains("/document/")) {
                // Already a document URI, extract document ID
                DocumentsContract.getDocumentId(treeUri)
            } else {
                // Tree URI, get tree document ID
                DocumentsContract.getTreeDocumentId(treeUri)
            }
            
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)
            
            val children = mutableListOf<Map<String, Any?>>()
            val cursor = context.contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE
                ),
                null, null, null
            )
            
            cursor?.use {
                while (it.moveToNext()) {
                    val childDocId = it.getString(0)
                    val name = it.getString(1)
                    val mimeType = it.getString(2)
                    val size = it.getLong(3)
                    val isDirectory = mimeType == DocumentsContract.Document.MIME_TYPE_DIR
                    
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childDocId)
                    
                    children.add(mapOf(
                        "uri" to childUri.toString(),
                        "name" to name,
                        "isDirectory" to isDirectory,
                        "size" to size,
                        "mimeType" to mimeType
                    ))
                }
            }
            
            result.success(children)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    /**
     * Check if app has persisted read+write permission for URI
     */
    private fun handleHasPersistedPermission(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("INVALID_ARGUMENT", "uri is required", null)
            return
        }
        
        val uri = Uri.parse(uriString)
        
        val persistedUris = context.contentResolver.persistedUriPermissions
        val hasPermission = persistedUris.any { 
            it.uri == uri && it.isReadPermission && it.isWritePermission 
        }
        result.success(hasPermission)
    }
    
    /**
     * Get a human-readable display name for a URI
     */
    private fun handleGetDisplayName(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("INVALID_ARGUMENT", "uri is required", null)
            return
        }
        
        val uri = Uri.parse(uriString)
        
        try {
            // For tree URIs, extract a friendly path from the document ID
            val docId = DocumentsContract.getTreeDocumentId(uri)
            // docId format is typically "primary:Music/FMP" or "XXXX-XXXX:Music/FMP"
            val displayPath = docId.substringAfter(":", docId)
            result.success(displayPath)
        } catch (e: Exception) {
            // Fallback: try to get display name via query
            try {
                val cursor = context.contentResolver.query(
                    uri,
                    arrayOf(OpenableColumns.DISPLAY_NAME),
                    null, null, null
                )
                cursor?.use {
                    if (it.moveToFirst()) {
                        val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIndex >= 0) {
                            result.success(it.getString(nameIndex))
                            return
                        }
                    }
                }
            } catch (_: Exception) {}
            
            // Final fallback: return the URI as-is
            result.success(uriString)
        }
    }
}
