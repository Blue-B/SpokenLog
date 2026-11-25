package io.github.blueb.spokenlog_audio

import androidx.core.content.FileProvider

/** Own subclass so the manifest merger keeps it apart from other plugins' FileProviders. */
class UpdateFileProvider : FileProvider()
