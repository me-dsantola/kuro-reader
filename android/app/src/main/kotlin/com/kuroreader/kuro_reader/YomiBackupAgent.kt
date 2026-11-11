package com.kuroreader.kuro_reader

import android.app.backup.BackupAgentHelper
import android.app.backup.FileBackupHelper
import android.app.backup.SharedPreferencesBackupHelper

class YomiBackupAgent : BackupAgentHelper() {
    override fun onCreate() {
        super.onCreate()
        addHelper(
            "yomi_prefs_backup",
            SharedPreferencesBackupHelper(this, "yomi_auto_backup_prefs"),
        )
        addHelper(
            "yomi_file_backup",
            FileBackupHelper(this, "yomi_auto_backup.txt"),
        )
    }
}
