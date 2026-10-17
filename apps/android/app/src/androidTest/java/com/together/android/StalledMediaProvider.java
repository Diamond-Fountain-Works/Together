package com.together.android;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.FileNotFoundException;
import java.io.IOException;

/** Test APK only. Platform Java avoids a dependency on the target app's Kotlin class loader. */
public final class StalledMediaProvider extends ContentProvider {
    private ParcelFileDescriptor writer;

    @Override public boolean onCreate() { return true; }
    @Override public String getType(Uri uri) { return "image/png"; }

    @Override public synchronized Cursor query(Uri uri, String[] projection, String selection, String[] args, String order) {
        boolean status = "status".equals(uri.getLastPathSegment());
        MatrixCursor result = new MatrixCursor(new String[] { status ? "opened" : OpenableColumns.DISPLAY_NAME });
        result.addRow(new Object[] { status ? (writer == null ? 0 : 1) : "synthetic-stalled.png" });
        return result;
    }

    @Override public synchronized ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"r".equals(mode)) throw new FileNotFoundException("Read-only synthetic provider");
        try {
            if (writer != null) writer.close();
            ParcelFileDescriptor[] pipe = ParcelFileDescriptor.createPipe();
            writer = pipe[1]; // Retain an open writer; no bytes/EOF until explicitly released.
            return pipe[0];
        } catch (IOException e) { throw new FileNotFoundException(e.getMessage()); }
    }

    @Override public synchronized int delete(Uri uri, String selection, String[] args) {
        if (!"release".equals(uri.getLastPathSegment())) throw new UnsupportedOperationException();
        try { if (writer != null) writer.close(); } catch (IOException ignored) { }
        writer = null;
        return 1;
    }

    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] args) { throw new UnsupportedOperationException(); }
}
