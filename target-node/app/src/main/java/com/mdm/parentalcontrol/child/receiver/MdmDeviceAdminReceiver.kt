package com.mdm.parentalcontrol.child.receiver

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.UserManager
import android.util.Log

class MdmDeviceAdminReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i(TAG, "MDM Device Admin enabled")
        applyAntiTamperingPolicies(context)
    }

    override fun onProfileProvisioningComplete(context: Context, intent: Intent) {
        super.onProfileProvisioningComplete(context, intent)
        Log.i(TAG, "MDM Device Owner provisioning complete")
        applyAntiTamperingPolicies(context)
    }

    private fun applyAntiTamperingPolicies(context: Context) {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager ?: return
        val admin = ComponentName(context, MdmDeviceAdminReceiver::class.java)

        if (!dpm.isDeviceOwnerApp(context.packageName)) {
            Log.w(TAG, "App is not Device Owner yet, skipping DO-exclusive policies.")
            return
        }

        try {
            // 1. Prevent App Uninstallation
            dpm.setUninstallBlocked(admin, context.packageName, true)

            // 2. Prevent Safe Mode boot
            dpm.addUserRestriction(admin, UserManager.DISALLOW_SAFE_BOOT)

            // 3. Prevent Factory Reset
            dpm.addUserRestriction(admin, UserManager.DISALLOW_FACTORY_RESET)

            // 4. Prevent creating Guest accounts
            dpm.addUserRestriction(admin, UserManager.DISALLOW_ADD_USER)

            // 5. Prevent manual date/time modification (Zero Quota Hack)
            dpm.addUserRestriction(admin, UserManager.DISALLOW_CONFIG_DATE_TIME)
            dpm.setAutoTimeRequired(admin, true)

            // 6. Disable Debugging / ADB to prevent tampering
            dpm.addUserRestriction(admin, UserManager.DISALLOW_DEBUGGING_FEATURES)

            // 7. Tu dong cap quyen POST_NOTIFICATIONS (Android 13+)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                dpm.setPermissionGrantState(
                    admin,
                    context.packageName,
                    android.Manifest.permission.POST_NOTIFICATIONS,
                    DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED
                )
            }

            Log.i(TAG, "Successfully enforced enterprise anti-tampering restrictions.")
        } catch (e: Exception) {
            Log.e(TAG, "Error applying anti-tampering policies", e)
        }
    }

    companion object {
        private const val TAG = "MdmDeviceAdminReceiver"

        fun getComponentName(context: Context): ComponentName {
            return ComponentName(context, MdmDeviceAdminReceiver::class.java)
        }
    }
}
