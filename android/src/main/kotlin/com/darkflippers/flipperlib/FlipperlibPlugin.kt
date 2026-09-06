package com.darkflippers.flipperlib

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Raw-USB host side of the DFU / recovery stack. Dart drives the STM32
 * bootloader through libusb over a file descriptor; this class is the only
 * owner of the underlying [UsbDeviceConnection].
 *
 * Invariants (the Dart side relies on them):
 *  - at most one connection is open at a time; `open` replaces the previous one;
 *  - the connection is closed only on `close(fd)` / `closeAll` from Dart or when
 *    `open` replaces it — never on the detach broadcast, so a reused descriptor
 *    number can not be picked up under a live libusb handle;
 *  - at most one `open` waits for the permission dialog; a second one fails
 *    with `busy` instead of queueing.
 *
 * Everything runs on the main thread: channel calls, broadcasts and results.
 */
class FlipperlibPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val METHOD_CHANNEL = "flipperlib/dfu"
        private const val EVENT_CHANNEL = "flipperlib/dfu/events"
        private const val ACTION_USB_PERMISSION = "com.darkflippers.flipperlib.USB_PERMISSION"
        private const val DFU_VENDOR_ID = 0x0483
        private const val DFU_PRODUCT_ID = 0xDF11
    }

    private lateinit var context: Context
    private var manager: UsbManager? = null
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null

    private var connection: UsbDeviceConnection? = null
    private var pendingOpen: MethodChannel.Result? = null
    private var pendingDevice: UsbDevice? = null
    private var lastPresence: Boolean? = null

    private val systemReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val device = deviceExtra(intent) ?: return
            if (!isDfu(device)) return
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> publishPresence(true)
                UsbManager.ACTION_USB_DEVICE_DETACHED -> publishPresence(findDfuDevice() != null)
            }
        }
    }

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != ACTION_USB_PERMISSION) return
            val result = pendingOpen ?: return
            val device = pendingDevice
            pendingOpen = null
            pendingDevice = null
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            if (device == null) {
                result.error("no_device", "DFU device vanished while asking for permission", null)
            } else if (!granted) {
                result.error("permission_denied", "USB permission denied for the DFU device", null)
            } else {
                openNow(device, result)
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        manager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
        methods = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        events = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
        registerReceivers()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        unregisterReceivers()
        failPendingOpen("detached", "Plugin detached from the engine")
        closeConnection(null)
        methods?.setMethodCallHandler(null)
        methods = null
        events?.setStreamHandler(null)
        events = null
        sink = null
        manager = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isPresent" -> result.success(findDfuDevice() != null)
            "open" -> open(result)
            "close" -> {
                closeConnection(call.argument<Int>("fd"))
                result.success(null)
            }
            "closeAll" -> {
                failPendingOpen("cancelled", "Recovery cancelled")
                closeConnection(null)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        this.sink = sink
        lastPresence = null
        publishPresence(findDfuDevice() != null)
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        lastPresence = null
    }

    private fun open(result: MethodChannel.Result) {
        val usb = manager
        if (usb == null) {
            result.error("no_usb_host", "USB host service unavailable", null)
            return
        }
        if (pendingOpen != null) {
            result.error("busy", "Another open is waiting for USB permission", null)
            return
        }
        val device = findDfuDevice()
        if (device == null) {
            result.error("no_device", "No DFU device on the bus", null)
            return
        }
        if (usb.hasPermission(device)) {
            openNow(device, result)
            return
        }
        pendingOpen = result
        pendingDevice = device
        val intent = Intent(ACTION_USB_PERMISSION).setPackage(context.packageName)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        val pending = PendingIntent.getBroadcast(context, 0, intent, flags)
        usb.requestPermission(device, pending)
    }

    private fun openNow(device: UsbDevice, result: MethodChannel.Result) {
        val usb = manager
        if (usb == null) {
            result.error("no_usb_host", "USB host service unavailable", null)
            return
        }
        closeConnection(null)
        val opened = try {
            usb.openDevice(device)
        } catch (e: SecurityException) {
            null
        }
        if (opened == null) {
            result.error("open_failed", "UsbManager.openDevice failed for ${device.deviceName}", null)
            return
        }
        connection = opened
        result.success(mapOf("fd" to opened.fileDescriptor, "name" to device.deviceName))
    }

    private fun closeConnection(fd: Int?) {
        val current = connection ?: return
        if (fd != null && current.fileDescriptor != fd) return
        connection = null
        current.close()
    }

    private fun failPendingOpen(code: String, message: String) {
        val result = pendingOpen ?: return
        pendingOpen = null
        pendingDevice = null
        result.error(code, message, null)
    }

    private fun publishPresence(present: Boolean) {
        if (lastPresence == present) return
        lastPresence = present
        sink?.success(present)
    }

    private fun findDfuDevice(): UsbDevice? =
        manager?.deviceList?.values?.firstOrNull { isDfu(it) }

    private fun isDfu(device: UsbDevice): Boolean =
        device.vendorId == DFU_VENDOR_ID && device.productId == DFU_PRODUCT_ID

    private fun deviceExtra(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }

    private fun registerReceivers() {
        val systemFilter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        val permissionFilter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Attach / detach are protected system broadcasts: exporting the
            // receiver only lets the system reach it. The permission reply is
            // addressed to this package, so it stays private.
            context.registerReceiver(systemReceiver, systemFilter, Context.RECEIVER_EXPORTED)
            context.registerReceiver(permissionReceiver, permissionFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(systemReceiver, systemFilter)
            context.registerReceiver(permissionReceiver, permissionFilter)
        }
    }

    private fun unregisterReceivers() {
        try {
            context.unregisterReceiver(systemReceiver)
        } catch (_: IllegalArgumentException) {
        }
        try {
            context.unregisterReceiver(permissionReceiver)
        } catch (_: IllegalArgumentException) {
        }
    }
}
