package com.kuroreader.kuro_reader

import android.app.backup.BackupAgentHelper
import android.app.backup.FileBackupHelper
import android.app.backup.SharedPreferencesBackupHelper

class YomiBackupAgent : BackupAgentHelper() {
    override fun onCreate() {
        super.onCreate()
        addHelper(
            "kuro_prefs_backup",
            SharedPreferencesBackupHelper(this, "kuro_auto_backup_prefs", "yomi_auto_backup_prefs"),
        )
        addHelper(
            "kuro_file_backup",
            FileBackupHelper(this, "kuro_auto_backup.json", "yomi_auto_backup.txt"),
        )
    }
}
