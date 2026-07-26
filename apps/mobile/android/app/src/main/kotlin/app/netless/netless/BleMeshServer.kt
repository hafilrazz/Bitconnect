package app.netless.netless

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Android BLE peripheral: advertise + GATT server so peers can connect and write packets.
 */
class BleMeshServer(
    private val context: Context,
    private val onPacket: (fromAddress: String, payload: ByteArray) -> Unit,
    private val onPeersChanged: (peers: List<String>) -> Unit,
) {
    companion object {
        private const val TAG = "BleMeshServer"
        val SERVICE_UUID: UUID = UUID.fromString("6e65746c-0001-4000-8000-00805f9b34fb")
        val CHAR_UUID: UUID = UUID.fromString("6e65746c-0002-4000-8000-00805f9b34fb")
        val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private val bluetoothManager =
        context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? get() = bluetoothManager.adapter

    private var gattServer: BluetoothGattServer? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var characteristic: BluetoothGattCharacteristic? = null
    private val connected = ConcurrentHashMap<String, BluetoothDevice>()
    private var running = false

    private val gattCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            val addr = device.address
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connected[addr] = device
                Log.i(TAG, "central connected $addr")
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                connected.remove(addr)
                Log.i(TAG, "central disconnected $addr")
            }
            emitPeers()
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            if (characteristic.uuid == CHAR_UUID && value != null && value.isNotEmpty()) {
                onPacket(device.address, value)
            }
            if (responseNeeded) {
                gattServer?.sendResponse(
                    device,
                    requestId,
                    BluetoothGatt.GATT_SUCCESS,
                    offset,
                    value,
                )
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic,
        ) {
            gattServer?.sendResponse(
                device,
                requestId,
                BluetoothGatt.GATT_SUCCESS,
                offset,
                characteristic.value ?: ByteArray(0),
            )
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: android.bluetooth.BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            if (responseNeeded) {
                gattServer?.sendResponse(
                    device,
                    requestId,
                    BluetoothGatt.GATT_SUCCESS,
                    offset,
                    value,
                )
            }
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            Log.i(TAG, "advertising started")
        }

        override fun onStartFailure(errorCode: Int) {
            Log.e(TAG, "advertise failed: $errorCode")
        }
    }

    @SuppressLint("MissingPermission")
    fun start(): Boolean {
        if (running) return true
        val bt = adapter ?: return false
        if (!bt.isEnabled) return false

        gattServer = bluetoothManager.openGattServer(context, gattCallback) ?: return false
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val char = BluetoothGattCharacteristic(
            CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ or
                BluetoothGattCharacteristic.PERMISSION_WRITE,
        )
        val cccd = android.bluetooth.BluetoothGattDescriptor(
            CCCD_UUID,
            android.bluetooth.BluetoothGattDescriptor.PERMISSION_READ or
                android.bluetooth.BluetoothGattDescriptor.PERMISSION_WRITE,
        )
        char.addDescriptor(cccd)
        service.addCharacteristic(char)
        gattServer?.addService(service)
        characteristic = char

        advertiser = bt.bluetoothLeAdvertiser
        // Low-latency + max TX power: best practical software boost for discovery range.
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(true)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        // Empty scan response keeps advertising payload small and connectable.
        val scanResponse = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .build()
        try {
            advertiser?.startAdvertising(settings, data, scanResponse, advertiseCallback)
        } catch (_: Exception) {
            // Fallback if dual-payload advertising fails on some OEMs.
            advertiser?.startAdvertising(settings, data, advertiseCallback)
        }

        running = true
        emitPeers()
        return true
    }

    @SuppressLint("MissingPermission")
    fun stop() {
        if (!running) return
        try {
            advertiser?.stopAdvertising(advertiseCallback)
        } catch (_: Exception) {
        }
        try {
            gattServer?.close()
        } catch (_: Exception) {
        }
        gattServer = null
        characteristic = null
        advertiser = null
        connected.clear()
        running = false
        emitPeers()
    }

    @SuppressLint("MissingPermission")
    fun sendToConnectedCentrals(payload: ByteArray) {
        val server = gattServer ?: return
        val char = characteristic ?: return
        char.value = payload
        for (device in connected.values) {
            try {
                server.notifyCharacteristicChanged(device, char, false)
            } catch (_: Exception) {
            }
        }
    }

    fun connectedPeerIds(): List<String> = connected.keys().toList()

    private fun emitPeers() {
        onPeersChanged(connectedPeerIds())
    }
}
