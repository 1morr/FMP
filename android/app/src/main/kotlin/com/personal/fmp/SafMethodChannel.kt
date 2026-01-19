package com.personal.fmp

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class SafMethodChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // 检测文件/目录是否存在
            "exists" -> handleExists(call, result)
            
            // 获取文件大小
            "getFileSize" -> handleGetFileSize(call, result)
            
            // 读取文件指定范围的字节
            "readRange" -> handleReadRange(call, result)
            
            // 在目录中创建文件
            "createFile" -> handleCreateFile(call, result)
            
            // 写入数据到文件
            "writeToFile" -> handleWriteToFile(call, result)
            
            // 追加数据到文件
            "appendToFile" -> handleAppendToFile(call, result)
            
            // 删除文件
            "deleteFile" -> handleDeleteFile(call, result)
            
            // 列出目录内容
            "listDirectory" -> handleListDirectory(call, result)
            
            // 获取持久化权限状态
            "hasPersistedPermission" -> handleHasPersistedPermission(call, result)
            
            // 获取目录显示名称
            "getDisplayName" -> handleGetDisplayName(call, result)
            
            // 根据树 URI 构建文档 URI
            "buildDocumentUri" -> handleBuildDocumentUri(call, result)
            
            else -> result.notImplemented()
        }
    }
    
    private fun handleExists(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val uri = Uri.parse(uriString)
        try {
            val cursor = context.contentResolver.query(uri, null, null, null, null)
            val exists = cursor?.use { it.count > 0 } ?: false
            result.success(exists)
        } catch (e: Exception) {
            result.success(false)
        }
    }
    
    private fun handleGetFileSize(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val uri = Uri.parse(uriString)
        try {
            val cursor = context.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
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
    
    private fun handleReadRange(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val start = call.argument<Number>("start")!!.toLong()
        val length = call.argument<Number>("length")!!.toInt()
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
    
    private fun handleCreateFile(call: MethodCall, result: MethodChannel.Result) {
        val parentUriString = call.argument<String>("parentUri")!!
        val fileName = call.argument<String>("fileName")!!
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        
        val parentUri = Uri.parse(parentUriString)
        try {
            val fileUri = DocumentsContract.createDocument(
                context.contentResolver,
                parentUri,
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
    
    private fun handleWriteToFile(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val data = call.argument<ByteArray>("data")!!
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
    
    private fun handleAppendToFile(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val data = call.argument<ByteArray>("data")!!
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
    
    private fun handleDeleteFile(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val uri = Uri.parse(uriString)
        
        try {
            val deleted = DocumentsContract.deleteDocument(context.contentResolver, uri)
            result.success(deleted)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
    
    private fun handleListDirectory(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val treeUri = Uri.parse(uriString)
        
        try {
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri)
            )
            
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
                    val docId = it.getString(0)
                    val name = it.getString(1)
                    val mimeType = it.getString(2)
                    val size = it.getLong(3)
                    val isDirectory = mimeType == DocumentsContract.Document.MIME_TYPE_DIR
                    
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                    
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
    
    private fun handleHasPersistedPermission(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val uri = Uri.parse(uriString)
        
        val persistedUris = context.contentResolver.persistedUriPermissions
        val hasPermission = persistedUris.any { 
            it.uri == uri && it.isReadPermission && it.isWritePermission 
        }
        result.success(hasPermission)
    }
    
    private fun handleGetDisplayName(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")!!
        val uri = Uri.parse(uriString)
        
        try {
            // 对于 tree URI，尝试获取友好的路径名称
            val docId = DocumentsContract.getTreeDocumentId(uri)
            // docId 格式通常是 "primary:Music/FMP" 或 "XXXX-XXXX:Music/FMP"
            val displayPath = docId.substringAfter(":", docId)
            result.success(displayPath)
        } catch (e: Exception) {
            result.success(uriString)
        }
    }
    
    private fun handleBuildDocumentUri(call: MethodCall, result: MethodChannel.Result) {
        val treeUriString = call.argument<String>("treeUri")!!
        val documentId = call.argument<String>("documentId")!!
        
        try {
            val treeUri = Uri.parse(treeUriString)
            val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
            result.success(documentUri.toString())
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
}
